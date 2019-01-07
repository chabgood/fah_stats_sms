#require 'pry'
require 'httparty'
require 'action_view'
require 'twilio-ruby'
require 'json'
require 'dotenv'

Dotenv.load

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
    @to =  ENV["TO"]
  end

  def run
    api_total = get_data
    file_hash = load_file
    return if api_total[:stats] == file_hash["contributed"]
    update_total(api_total)
    send_sms(api_total)
  end

  private

  def send_sms(api_total)
    stats = number_to_human(api_total[:stats], precision: 5)
    rank = number_to_human(api_total[:rank], precision: 5)
    self.client.messages.create(from: self.from, to: self.to,
      body: "Current Team Total: #{stats} \n Total Rank: #{rank}"
    )
  end

  def update_total(api_total)
    File.open("../fah.json", "w") do |f|
      f.write({ contributed: api_total }.to_json)
    end
  end

  def load_file
    file = File.read("../fah.json")
    return JSON.parse(file)
  end

  def get_data
    data_rank = self.class.get('/user/MrMoo').parsed_response
    return { stats: score.to_i, rank: data_rank['rank'].to_i }
  end
end

fah = FahStatsSms.new
fah.run
