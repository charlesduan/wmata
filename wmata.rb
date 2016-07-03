#!/usr/bin/ruby

require 'net/http'
require 'uri'
require 'json'
require 'date'

class Cache
  def initialize
    @cache = {}
  end

  def get(type, key, valid)
    time = Time.now
    entry = @cache[[type, key]]
    if entry and entry[0] + valid > time
      return entry[1]
    else
      res = yield
      @cache[[type, key]] = [ time, res ]
      return res
    end
  end
end

class Wmata

  API_URL = URI.parse("https://api.wmata.com")

  def initialize(key)
    @http = Net::HTTP.start(API_URL.host, API_URL.port,
                            :use_ssl => true)
    @api_key = key
    @cache = Cache.new
  end

  def request(endpoint, params = {})
    uri = API_URL + endpoint
    uri.query = URI.encode_www_form(params) unless params.empty?
    request = Net::HTTP::Get.new(uri.request_uri)
    request['api_key'] = @api_key
    response = @http.request(request)

    if response.code == '429' and response['Retry-After']
      delay = response['Retry-After'].to_i
      if delay < 5
        sleep response['Retry-After'].to_i
        response = @http.request(request)
      end
    end

    raise "Unexpected response #{response.code}" unless response.code == '200'
    return JSON.parse(response.body)
  end

  def lines
    res = {}
    out = @cache.get('lines', '', 86400) {
      request('Rail.svc/json/jLines')
    }
    out['Lines'].each do |line|
      res[line['LineCode']] = line['DisplayName']
    end
    return res
  end

  def stations(line_code)
    res = {}
    raise "Unknown line code #{line_code}" unless lines[line_code]
    @cache.get('stations', line_code, 86400) {
      request('Rail.svc/json/jStations', 'LineCode' => line_code)
    }['Stations'].each do |station|
      res[station['Name']] = station['Code']
    end
    return res
  end

  def all_stations
    res = {}
    @cache.get('stations', '', 86400) {
      request('Rail.svc/json/jStations')
    }['Stations'].each do |station|
      res[station['Code']] = station
    end
    return res
  end

  def station_info(code)
    station = all_stations[code]
    raise "Unknown station #{code}" unless station
    return station
  end

  def station_name(code)
    station_info(code)['Name']
  end

  def next_trains(stations)
    all = all_stations
    stations = [ stations ].flatten
    bad_stations = stations.reject { |x| all.include?(x) }.join(", ")
    raise "Invalid station(s) #{bad_stations}" unless bad_stations.empty?

    stationstring = stations.join(",")
    @cache.get('next_trains', stationstring, 10) {
      request('StationPrediction.svc/json/GetPrediction/' + stationstring)
    }['Trains'].map { |train|
      PredictionInfo.new(train)
    }.sort
  end

  def rail_incidents
    @cache.get('rail_incidents', '', 20) {
      request('Incidents.svc/json/Incidents')
    }['Incidents'].map { |incident|
      IncidentInfo.new(incident)
    }
  end

  def bus_path_info(route)
    @cache.get('bus_path', route, 3600) {
      request('Bus.svc/json/jRouteDetails', 'RouteID' => route)
    }
  end

  def bus_name(route)
    bus_path_info(route)['Name']
  end

  def bus_direction(route, dirnum)
    dir = (dirnum.to_s == '0') ? 'Direction0' : 'Direction1'
    info = bus_path_info(route)[dir]
    return [ info['DirectionText'], info['TripHeadsign'] ]
  end

  def bus_stops(route, dirnum)
    dir = (dirnum.to_s == '0') ? 'Direction0' : 'Direction1'
    info = bus_path_info(route)[dir]
    info['Stops'].map { |x| [ x['StopID'], x['Name'] ] }
  end

  def bus_routes
    res = {}
    @cache.get('bus_routes', '', 86400) {
      request('Bus.svc/json/jRoutes')
    }['Routes'].each do |x| 
      res[x['RouteID']] = x['Name']
    end
    return res
  end

  class IncidentInfo
    def initialize(incident)
      @incident = incident
    end

    INCIDENT_PRE = /(Orange|Red|Green|Yellow|Blue|Silver|\/)* Lines?: /
    def text
      @incident['Description'].sub(INCIDENT_PRE, "")
    end

    def date
      DateTime.parse(@incident['DateUpdated'])
    end

    def lines
      @incident['LinesAffected'].split(/;\s*/).reject(&:empty?)
    end

    def ==(other)
      puts "HERE"
      lines == other.lines && text == other.text
    end
    alias_method :eql?, :==
    def hash
      lines.hash & text.hash
    end
  end

  class PredictionInfo
    def initialize(prediction)
      @prediction = prediction
    end
    def car
      @prediction['Car']
    end
    def destination
      @prediction['DestinationCode']
    end
    def min
      @prediction['Min']
    end
    def group
      @prediction['Group']
    end
    def line
      @prediction['Line']
    end
    def location
      @prediction['LocationCode']
    end
    def min_for_sort
      case min
      when /^\d+$/ then min.to_i
      when "ARR" then -1
      when "BRD" then -2
      else 100000
      end
    end
    def <=>(other)
      min_for_sort <=> other.min_for_sort
    end
  end

end


