#!/usr/bin/env ruby

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
    @to = ENV["TO"]
  end

  def run
    data = self.class.get('/user/MrMoo/stats', query).parsed_response
    api_total = data['contributed'].to_i
    file = File.read("fah.json")
    file_hash = JSON.parse(file)
    return if api_total == file_hash["contributed"]  # exit early if there is no change
    send_sms(api_total)
  end

  private

  def send_sms(api_total)
    total_human = number_to_human(api_total, precision: 5)
    self.client.messages.create(from: self.from, to: self.to,
      body: "Current_total: #{total_human}"
    )
  end
end

fah = FahStatsSms.new
fah.run
