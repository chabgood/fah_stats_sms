require 'bundler/inline'

gemfile(true) do
  source 'https://rubygems.org'

  ruby '2.7.0'

  gem 'net-telnet'
  gem 'httparty'
  gem 'twilio-ruby'
  gem 'json'
  gem 'actionview'
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
  DIR=File.join(File.dirname(__FILE__), 'fah.json')
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
    @account_sid = ENV["ACCOUNT_SID"]
    @auth_token = ENV["AUTH_TOKEN"]
    @client = Twilio::REST::Client.new(account_sid, auth_token)
    @from = ENV["FROM"]
    @to = ENV["TO"]
  end

  def run
    api_total = get_data
    update_total(api_total)
    get_ppd
    get_gpus_running
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

  def update_total(api_total)
    File.open(DIR, "w") do |f|
      f.write({ overall_score: api_total[:overall_score], overall_rank: api_total[:overall_rank] }.to_json)
    end
  end

  def get_data
    data_rank = self.class.get("/user/MrMoo?passkey=#{ENV['PASSKEY']}").parsed_response
    self.json_data = data_rank
    data_rank_team = data_rank['teams'].select{ |hash| hash['name'] == "Curecoin"}.first
    team_score = data_rank_team['score']
    team_name = data_rank_team['name']
    return { overall_rank: data_rank['rank'].to_i, overall_score: data_rank['score'], team_name: team_name, team_score: team_score }
  end

  def get_ppd
    ppd_data = pop.cmd("ppd").scan(/^[0-9]*\.[0-9]*$/)&.last
    while ppd_data.nil?
      ppd_data = pop.cmd('ppd').scan(/^[0-9]*\.[0-9]*$/).last
      sleep 2
    end
    self.ppd = ppd_data
  end

  def get_gpus_running
    slots_data = 0
    slots_data = pop.cmd("slot-info").scan(/RUNNING/).length 
    while slots_data.zero?
      slots_data = pop.cmd('slot-info').scan(/RUNNING/).length 
      sleep 2
    end
    self.gpus_running = slots_data
  end

  def nvidia_temps_and_gpus_running
    data = `nvidia-smi --query-gpu=gpu_name,temperature.gpu --format=csv,noheader`
    arr = data.split("\n")
    arr.each do |card|
      card_data = card.split(",")
      self.table << "#{card_data[0]} - #{card_data[1]}C\n"
    end
  end

  def get_cards_ppd
   cards = pop.cmd('queue-info').scan(/"id":\s"(\d*)".*"ppd":\s*"([0-9]*)/).sort_by{ |card| card[0]}
   str=""
   cards.each do |card|
    str << "slot #{card[0]} - #{number_to_human(card[1], precision: 6)}\n"
   end
   self.cards_ppd = str
  end

end

# ActiveRecord::Base.establish_connection(
#     adapter:  'postgresql', # or 'postgresql' or 'sqlite3' or 'oracle_enhanced'
#     host:     'localhost',
#     database: 'fah',
#     username: 'chabgood',
#     password: ENV['DB_PW'] || ''
#   )


# class Database
  
#   attr_accessor :json_data
#   def initialize(json)
#     @json_data = json
#   end

#   class User < ActiveRecord::Base
#     has_many :teams
#     has_many :projects
#     has_many :user_data,class_name: 'UserData'
#   end

#   class UserData < ActiveRecord::Base
#     self.table_name  = 'user_data'
#     belongs_to :team
#   end

#   class Team < ActiveRecord::Base
#     belongs_to :user
#     has_many :team_data, class_name: 'TeamData'
#   end

#   class TeamData < ActiveRecord::Base
#     self.table_name  = 'team_data'
#     belongs_to :user
#   end

#   class Project < ActiveRecord::Base
#     belongs_to :user
#   end

#   def run
#     u  = User.find_or_create_by(name: json_data['name'])
#     u.user_data.find_or_create_by(id: json_data['id'], score: json_data['score']) do |user_data|
#       user_data.rank = json_data['rank']
#       user_data.wus =  json_data['wus']
#     end

#     json_data['teams'].each do |team|
#       t = u.teams.find_or_create_by(name: team['name'], team: team['team'])
#       t.team_data.find_or_create_by(score: team['score']) do |team_data|
#         team_data.wus = team['wus']
#       end
#     end
#     a = Project.pluck(:name)
#     b = json_data['projects']
#     ar = (a-b) + (b-a)
#     ar.each do |ar|
#       u.projects.create(name: ar)
#     end
#   end

# end
fah = FahStatsSms.new
fah.run
# fah.update_database
