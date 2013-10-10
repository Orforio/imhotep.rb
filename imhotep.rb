require 'nokogiri'
require 'open-uri'

URL = "http://www.bbc.co.uk/education/guides/ztndmp3/revision" # Hardcoded for testing
PROXY = "http://www-cache.reith.bbc.co.uk:80" # Standard BBC Reith proxy
REGEX_GRAPHICS = /\/content\/(z\w+)\/(large|medium|small)/

class Scraper
	#example = Page.new(URL)

	#puts example.extract_info
end

class Page
	@page
	@images

	def initialize(url)
		@page = Nokogiri::HTML(open(url, :proxy => PROXY))
		@images = Array.new
	end

	def extract_info
		@page.xpath('//article//img/@src').each do |image|
			@images << {:pid => image.content[REGEX_GRAPHICS, 1], :size => image.content[REGEX_GRAPHICS, 2]}
		end
		@images
	end
end

class MigrationLog
	#TODO
end

example = Page.new(URL)

puts example.extract_info