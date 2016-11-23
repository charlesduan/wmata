#!/usr/bin/ruby

require 'json'
require 'uri'
require 'date'
require 'eventmachine'
require './em-cache'
require 'em-http-request'

class EM::CapitalBikeshare

  def initialize(&block)
    @cache = EmCache.new(&block)
  end

  def request(uri)
    uri = URI.parse(uri)
    res = EM::DefaultDeferrable.new
    @cache.resolve_dns(uri) do |ip|
      request = EM::HttpRequest.new(uri, :host => ip).get
      request.errback { res.fail("Error requesting #{uri}") }
      request.callback do
        case request.response_header.http_status
        when 200
          begin
            res.succeed(JSON.parse(request.response))
          rescue
            res.fail("Error processing #{uri} response")
          end
        else
          res.fail(
            "Error requesting #{uri}: #{request.response_header.http_status}"
          )
        end
      end
    end
    return res
  end

  INFO_URL =
    'https://gbfs.capitalbikeshare.com/gbfs/en/station_information.json'
  STATUS_URL = 'https://gbfs.capitalbikeshare.com/gbfs/en/station_status.json'


  def all_status(&block)
    @cache.get('station_status', '', 60, proc { request(STATUS_URL) }, &block)
  end

  def all_info(&block)
    @cache.get('station_info', '', 86400, proc { request(INFO_URL) }, &block)
  end

  def station_name(station_id)
    station_id = station_id.to_s
    all_info do |info|
      station = info['data']['stations'].find { |x|
        x['station_id'] == station_id
      }
      yield(nil) unless station
      yield(station['name'])
    end
  end

  def station_status(station_id)
    station_id = station_id.to_s
    all_status do |status|
      station = status['data']['stations'].find { |x|
        x['station_id'] == station_id
      }
      yield(StationStatus.new(station))
    end
  end

  class StationStatus
    def initialize(status)
      @status = status
    end
    def num_bikes_available
      return @status['num_bikes_available']
    end
    def num_docks_available
      return @status['num_docks_available']
    end
    def num_disabled
      return @status['num_bikes_disabled'] + @status['num_docks_disabled']
    end

    def status_string(width)
      b, d = num_bikes_available, num_docks_available
      res = case width
            when 5 then "%2d/%2d" % [ b, d ]
            when 9 then "%2d b/%2d d" % [ b, d ]
            when 17 then "%2d bike%s/%2d dock%s" % \
              [ b, b == 1 ? ' ' : 's', d, d == 1 ? ' ' : 's' ]
            else raise "Invalid width"
            end
      return res
    end

    def working
      %w(is_installed is_renting is_returning).each do |flag|
        return false if @status[flag] != 1
      end
      return true
    end
  end

end

