require 'bundler/inline'
require 'net/telnet'

gemfile do
  source 'https://rubygems.org'
  ruby '2.7.0'

  gem 'httparty'
  gem 'twilio-ruby'
  gem 'pry'
  gem 'json'
  gem 'actionview'
  gem 'dotenv'
end

require 'dotenv/load'
require 'pry'
require 'httparty'
require 'action_view'
require 'twilio-ruby'
require 'json'


class FahStatsSms
  include HTTParty
  include ActionView::Helpers::NumberHelper
  DIR=File.join(File.dirname(__FILE__), 'fah.json')
  base_uri 'https://api.foldingathome.org/'

  attr_accessor :number, :table, :query, :account_sid, :auth_token, :client, :to, :from, :ppd, :gpus_running

  def initialize()
    @number = 0
    @query = { query: {  passkey: ENV["PASSKEY"], team: ENV["TEAM"], header: { 'Content-Type' => 'application/json' } } }
    @ppd = 0
    @gpus_running = 0
    @table = ""
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
    #return if api_total[:stats] == file_hash["stats"]
    update_total(api_total)
    get_ppd
    nvidia_temps_and_gpus_running
    send_sms(api_total)
  end

  private

  def send_sms(api_total)
    overall_score = number_to_human(api_total[:overall_score], precision: 5)
    overall_rank = number_to_human(api_total[:overall_rank], precision: 5)
    team_score = number_to_human(api_total[:team_score], precision: 5)
    ppd = number_to_human(self.ppd, precision: 5)
    self.client.messages.create(from: self.from, to: self.to, body: "Score: #{overall_score} \n Total Rank: #{overall_rank} \n Team: #{api_total[:team_name]} \n Team Total: #{team_score} \n PPD: #{ppd} \n GPUS: #{self.gpus_running}\n\nGPU TEMPS:\n#{self.table}")
  end

  def update_total(api_total)
    File.open(DIR, "w") do |f|
      f.write({ overall_score: api_total[:overall_score], overall_rank: api_total[:overall_rank] }.to_json)
    end
  end

  def load_file
    file = File.read(DIR)
    return JSON.parse(file)
  end

  def get_data
    data_rank = self.class.get('/user/MrMoo').parsed_response
    data_rank_team = data_rank['teams'].select{ |hash| hash['name'] == "Curecoin"}.first
    team_score = data_rank_team['score']
    team_name = data_rank_team['name']
    return { overall_rank: data_rank['rank'].to_i, overall_score: data_rank['score'], team_name: team_name, team_score: team_score }
  end

  def get_ppd
    pop = Net::Telnet::new("Host" => "localhost", "Port" => 36330)
    pop.cmd("ppd") { |c| self.ppd = c.scan(/^[0-9]*\.[0-9]*$/).last }
  end

  def nvidia_temps_and_gpus_running
    data = `nvidia-smi --query-gpu=gpu_name,temperature.gpu --format=csv,noheader`
    arr = data.split("\n")
    self.gpus_running = arr.length
    arr.each do |card|
      card_data = card.split(",")
      self.table << "#{card_data[0]} - #{card_data[1]}C\n"
    end
  end
end

fah = FahStatsSms.new
fah.run
