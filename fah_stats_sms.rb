require 'bundler/inline'

gemfile(true) do
  source 'https://rubygems.org'

  ruby '2.7.0'

  gem 'net-telnet'
  gem 'httparty'
  gem 'twilio-ruby'
  gem 'json'
  gem 'actionview'
  gem 'activesupport'
  gem 'dotenv'
  gem 'chronic'
  gem 'pry'
end

require 'net/telnet'
require 'dotenv/load'
require 'httparty'
require 'action_view'
require 'twilio-ruby'
require 'json'
# require 'active_record'
class FahStatsSms
  include HTTParty
  include ActionView::Helpers::NumberHelper
  base_uri 'https://api.foldingathome.org/'

  attr_accessor :number, :pop, :table, :query, :account_sid, :auth_token, :client, :to, :from, :ppd, :gpus_running, :json_data, :cards_ppd

  def initialize()
    @number = 0
    @query = { query: {  passkey: ENV['PASSKEY'], team: ENV["TEAM"], header: { 'Content-Type' => 'application/json' } } }
    @ppd = 0
    @gpus_running = 0
    @table = ""
    @pop = Net::Telnet::new("Host" => "localhost", "Port" => 36330)
    @json_data = {}
    @cards_ppd = []
    initialize_twilio_info
  end

  def initialize_twilio_info
    @account_sid = ENV["ACCT_SID"]
    @auth_token = ENV["AUTH_TOKEN"]
    @client = Twilio::REST::Client.new(@account_sid, @auth_token)
    @from = ENV["FROM"]
    @to = ENV["TO"]
  end

  def run
    api_total = get_data
    nvidia_temps_and_gpus_running
    get_cards_ppd
    send_sms(api_total)
    # update_database
  end

  private
  
  def update_database
    # db = Database.new(json_data)
    # db.run
  end
  
  def send_sms(api_total)
    overall_score = number_to_human(api_total[:overall_score], precision: 5)
    overall_rank = number_to_human(api_total[:overall_rank], precision: 5)
    team_score = number_to_human(api_total[:team_score], precision: 5)
    ppd = number_to_human(self.ppd, precision: 5)
    self.client.messages.create(
      from: self.from, 
      to: self.to, 
      body: "Score: #{overall_score} \n Total Rank: #{overall_rank} \n Team: #{api_total[:team_name]} \n Team Total: #{team_score} \n PPD: #{ppd} \n GPUS: #{self.gpus_running}\n\nGPU TEMPS:\n#{self.table} \n #{self.cards_ppd}"
    )
  end

  def get_data
    data_rank = self.class.get("/user/MrMoo?passkey=#{ENV['PASSKEY']}").parsed_response
    self.json_data = data_rank
    data_rank_team = data_rank['teams'].select{ |hash| hash['name'] == "Curecoin"}.first
    team_score = data_rank_team['score']
    team_name = data_rank_team['name']
    return { overall_rank: data_rank['rank'].to_i, overall_score: data_rank['score'], team_name: team_name, team_score: team_score }
  end

  def nvidia_temps_and_gpus_running
    data = `nvidia-smi --query-gpu=gpu_name,temperature.gpu --format=csv,noheader`
    arr = data.split("\n")
    arr.each do |card|
      card_data = card.split(",")
      self.table << "#{card_data[0]} - #{card_data[1]}C\n"
    end
    self.gpus_running = arr.length
  end

  def get_cards_ppd
    cards = pop.cmd('queue-info').scan(/"id":\s"(\d*)".*"ppd":\s*"([0-9]*)/).sort_by{ |card| card[0]}.find_all{ |n| n[1] != "0" }
   while cards.length.zero?
     cards = pop.cmd('queue-info').scan(/"id":\s"(\d*)".*"ppd":\s*"([0-9]*)/).sort_by{ |card| card[0]}.find_all{ |n| n[1] != "0" }
    str = cards.inject("") do |str, card|
      str << "slot #{Integer(card[0], 10)} - #{number_to_human(card[1], precision: 6)}\n"
    end.uniq
    self.ppd = cards.sum{ |n| n[1].to_i}
    self.cards_ppd = str
  end
  end

end

fah = FahStatsSms.new
fah.run
