require "net/http"
require "uri"
require 'retriable'
require 'active_support/all'
require './analyser'

glob = "dump/out*.jpg"

raise("You must set a POST_URL env variable - this is where kartalytics will send its data") if ENV['POST_URL'].blank?

keep_files = !!ENV['KEEP_FILES']
uri = URI.parse(ENV['POST_URL'])

Logger = ActiveSupport::Logger.new('analyser.log')

loop do
  events = []

  begin
    Dir.glob(glob).sort_by {|file|
      File.ctime(file)
    }.each do |filename|
      start = Time.now
      event = Analyser.analyse!(filename)

      puts "#{File.basename(filename)} => #{event.inspect} - Time taken: #{Time.now - start}"

      if keep_files
        new_name = filename.to_s.sub('out', 'processed')
        File.rename(filename, new_name)
      else
        File.unlink(filename)
      end

      if event
        events.push event
      end
    end
  rescue Magick::ImageMagickError => e
    puts "RMagick error #{e}"
  end

  if events.any?
    payload = {
      events: events
    }

    request = Net::HTTP::Post.new(uri.path)
    request.content_type = "application/json"
    request.body = payload.to_json

    puts request.body
    response = nil

    Retriable.retriable on: [Timeout::Error, Errno::ECONNRESET] do
      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request request
      end
    end

    puts "Sending #{events.length} event(s). Response #{response.body}"
  end
  sleep(0.2)
end

