#!/usr/bin/ruby

require 'uri'
require 'json'
require 'date'
require 'eventmachine'
require 'em-http-request'

class EM::Wmata

  class Cache
    def initialize
      @cache = {}
    end

    def get(type, key, valid, data_proc)
      time = Time.now
      entry = @cache[[type, key]]
      if entry and entry[0] + valid > time
        yield(entry[1])
      else
        deferrable = data_proc.call
        deferrable.callback { |data|
          @cache[[type, key]] = [ Time.now, data ]
          yield(data)
        }
      end
    end
  end


  API_URL = URI.parse("https://api.wmata.com")

  def initialize(key)
    @api_key = key
    @cache = Cache.new
  end

  def request(endpoint, params = {})
    uri = API_URL + endpoint
    request = EM::HttpRequest.new(uri).get(:query => params,
                                           :head => { 'api_key' => @api_key })
    res = EM::DefaultDeferrable.new
    request.errback { res.fail }
    request.callback do
      case request.response_header.http_status
      when 200
        res.succeed(JSON.parse(request.response))
      when 429
        maybe_retry(request, res) do
          new_res = request(endpoint, params)
          new_res.errback { res.fail }
          new_res.callback { |*args| res.succeed(*args) }
        end
      else
        res.fail
      end
    end
    return res
  end

  def maybe_retry(request, res)
    if request.response_header['Retry-After']
      delay = response['Retry-After'].to_i
      if delay < 5
        yield
      else
        res.fail
      end
    end
  end

  def lines
    @cache.get('lines', '', 86400, proc {
      request('Rail.svc/json/jLines')
    }) do |data|
      res = {}
      data['Lines'].each do |line|
        res[line['LineCode']] = line['DisplayName']
      end
      yield(res)
    end
  end

  def stations(line_code)
    lines do |the_lines|
      raise "Unknown line code #{line_code}" unless the_lines[line_code]

      @cache.get('stations', line_code, 86400, proc {
        request('Rail.svc/json/jStations', 'LineCode' => line_code)
      }) do |data|
        res = {}
        data['Stations'].each do |station|
          res[station['Name']] = station['Code']
        end
        yield(res)
      end
    end
  end

  def all_stations
    @cache.get('stations', '', 86400, proc {
      request('Rail.svc/json/jStations')
    }) do |data|
      res = {}
      data['Stations'].each do |station|
        res[station['Code']] = station
      end
      yield res
    end
  end

  def station_info(code)
    all_stations do |stations|
      raise "Unknown station #{code}" unless stations[code]
      yield stations[code]
    end
  end

  def station_name(code)
    station_info(code) do |info|
      yield info['Name']
    end
  end

  def next_trains(stations)
    stations = [ stations ].flatten
    all_stations do |all|
      bad_stations = stations.reject { |x| all.include?(x) }.join(", ")
      raise "Invalid station(s) #{bad_stations}" unless bad_stations.empty?

      stationstring = stations.join(",")
      @cache.get('next_trains', stationstring, 10, proc {
        request('StationPrediction.svc/json/GetPrediction/' + stationstring)
      }) do |data|
        yield(data['Trains'].map { |train| PredictionInfo.new(train) }.sort)
      end
    end
  end

  def bus_stop_name(station)
    @cache.get('next_bus', station, 10, proc {
      request('NextBusService.svc/json/jPredictions', 'StopID' => station)
    }) do |data|
      yield(data['StopName'])
    end
  end

  def next_buses(station)
    @cache.get('next_bus', station, 10, proc {
      request('NextBusService.svc/json/jPredictions', 'StopID' => station)
    }) do |data|
      yield(data['Predictions'].map { |pred| BusPrediction.new(pred) })
    end
  end

  def rail_incidents
    @cache.get('rail_incidents', '', 20, proc {
      request('Incidents.svc/json/Incidents')
    }) do |data|
      yield(data['Incidents'].map { |incident| IncidentInfo.new(incident) })
    end
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
      lines == other.lines && text == other.text
    end
    alias_method :eql?, :==
    def hash
      lines.hash & text.hash
    end
  end

  class BusPrediction
    def initialize(prediction)
      @prediction = prediction
    end

    def group
      @prediction['DirectionNum']
    end
    def direction
      @prediction['DirectionText']
    end
    def min
      @prediction['Minutes']
    end
    def line
      @prediction['RouteID']
    end
    def <=>(other)
      min <=> other.min
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
    def destination_name
      @prediction['DestinationName']
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

