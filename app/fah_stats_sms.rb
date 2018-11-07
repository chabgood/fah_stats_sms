require 'pry'
require 'httparty'
require 'action_view'
require 'twilio-ruby'
require 'json'
require 'dotenv/load'


class FahStatsSms
  include HTTParty
  include ActionView::Helpers::NumberHelper

  base_uri 'https://api.foldingathome.org/'

  attr_accessor :number, :query, :account_sid, :auth_token, :client, :to, :from

  def initialize()
    @number = 0
    @query = { query: {  passkey: ENV["PASSKEY"], team: ENV["TEAM"], header: { 'Content-Type' => 'application/json' } } }
    initialize_twilio_info
  end

  def initialize_twilio_info
    @account_sid = ENV["ACCT_SID"]
    @auth_token = ENV["AUTH_TOKEN"]
    @client = Twilio::REST::Client.new(account_sid, auth_token)
    @from = ENV["FROM"]
    @to = ENV["TO"]
  end

  def run
    data = self.class.get('/user/MrMoo/stats', query).parsed_response
    api_total = data['contributed'].to_i

    file = File.read("fah.json")
    file_hash = JSON.parse(file)
    contributed = file_hash["contributed"].to_i
    return if api_total == contributed  # exit early if there is no change
    if api_total < contributed
      p "api_total < contributed"
      File.open("fah.json", "w") do |f|
        f.write({ contributed: api_total, current_work: 0 }.to_json)
      end
    elsif api_total > contributed
      p "api_total > contributed"
      File.open("fah.json", "w") do |f|
        current_work = (api_total - contributed) == api_total ? 0 : api_total - contributed
        f.write({ contributed: api_total, current_work: current_work }.to_json)
      end
    end

    total_human = number_to_human(file_hash['contributed'], precision: 5)
    current_work = number_to_human(file_hash["current_work"], precision: 5)
    client.messages.create(
      from: from,
      to: to,
      body: "
      Current_total: #{total_human}, \nCurrent_work: #{current_work}"
    )
  end

end

fah = FahStatsSms.new
fah.run
