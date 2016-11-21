require 'eventmachine'

class EmCache
  def initialize(&block)
    @cache = {}
    @count = 0
    @errproc = block
  end

  def resolve_dns(uri, &block)
    uri = URI.parse(uri) if uri.is_a?(String)
    host = uri.host
    get('DNS', host, 600, proc {
      d = EM::DNS::Resolver.resolve(host)
      res = EM::DefaultDeferrable.new
      d.errback { res.fail("Failed resolving DNS of #{host} for #{uri}") }
      d.callback { |r|
        if r.is_a?(Array) and r.first
          res.succeed(r.first)
        else
          res.fail("No DNS result for #{host} of #{uri}")
        end
      }
      res
    }, &block)
  end

  def get(type, key, valid, data_proc, &block)
    @count += 1
    time = Time.now
    entry = @cache[[type, key]]
    if entry.is_a?(CachePending)
      entry.add_block(block)
    elsif entry and entry[0] + valid > time
      yield(entry[1])
    else
      @cache[[type, key]] = CachePending.new
      deferrable = data_proc.call
      deferrable.callback { |data|
        pending = @cache[[type, key]]
        @cache[[type, key]] = [ Time.now, data ]
        yield(data)
        pending.execute(data) if pending.is_a?(CachePending)
      }
      deferrable.errback { |msg|
        @cache[[type, key]] = nil
        @errproc.call("Failed in cache: #{msg}")
      }
    end
  end

  class CachePending
    def initialize
      @blocks = []
    end
    def add_block(block)
      @blocks.push(block)
    end
    def execute(data)
      @blocks.each do |block|
        block.call(data)
      end
    end
  end
end



