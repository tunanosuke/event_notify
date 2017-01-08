require "bundler/setup"
require "google_calendar"
require "json"
require "net/http"
require "uri"
require "pry"

def schedule_notification_message(schedule, message)
  schedule.each do |raw|
    start_time = Time.parse(raw["start"]["dateTime"])
    end_time = Time.parse(raw["end"]["dateTime"])
    message << "#{format('%02d', start_time.hour)}:#{format('%02d', start_time.min)}-"
    message << "#{format('%02d', end_time.hour)}:#{format('%02d',end_time.min)}\n"
    message << "#{raw["summary"]}\n"
  end
end

def to_do_notification_message(list, message)
  list.each do |raw|
    message << "#{raw["summary"]}\n"
  end
end

# authentication
options = JSON.parse(File.read("config/service_account.json"))
key = OpenSSL::PKey::RSA.new(options["private_key"])

client = Signet::OAuth2::Client.new(
  token_credential_uri: options["token_uri"],
  audience: options["token_uri"],
  scope: "https://www.googleapis.com/auth/calendar",
  issuer: options["client_email"],
  signing_key: key
)
client.fetch_access_token!

# google calendar connection
connection = Google::Connection.new({}, client)
calendar = Google::Calendar.new({ calendar: "#{CALENDAR_ID}" }, connection)
start_min = (Date.today + 1).to_time
start_max = (Date.today + 2).to_time
events = calendar.find_events_in_range(start_min, start_max)

schedule = []
list = []
events.each do |event|
  next if Time.parse(event.start_time).getlocal < Time.now
  if event.raw["start"]["dateTime"] || event.raw["end"]["dateTime"]
    schedule << event.raw
  elsif event.raw["start"]["date"] || event.raw["end"]["date"]
    list << event.raw
  end
end

# notification message
message = "\n【明日の予定】\n"
schedule.empty? ? message << "なし\n" : schedule_notification_message(schedule, message)

message << "\n【やることリスト】\n"
list.empty? ? message << "なし\n" : to_do_notification_message(list, message)

# line notify
uri = URI.parse("https://notify-api.line.me/api/notify")
https = Net::HTTP.new(uri.host, uri.port)
https.use_ssl = true

req = Net::HTTP::Post.new(uri.request_uri)
req["Authorization"] = "Bearer #{LINE_ACCESS_TOKEN}"
req["Content-Type"] = "application/x-www-form-urlencoded;charset=UTF-8"
req.set_form_data({ message: message })

https.request(req)
