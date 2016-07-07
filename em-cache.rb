require 'eventmachine'

class EmCache
  def initialize
    @cache = {}
    @count = 0
  end

  def get(type, key, valid, data_proc, &block)
    @count += 1
    count = @count
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
        raise "Failed in cache: #{msg}"
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



