require 'rubygems'
require 'logger'
require 'highline'
require 'lib/rreplizer'

logger = Logger.new('rreplizer.log')
logger.level = Logger::ERROR

# set account info
opt = {}
hl = HighLine.new
puts 'Please input your twitter and gmail account'
options = {}
options[:twitter_id]   = hl.ask('twitter id> ')
options[:twitter_pass] = hl.ask('twitter pass> ') {|inp| inp.echo = '*'}
options[:gmail_id]     = hl.ask('gmail id(without @gmail.com)> ')
options[:gmail_pass]   = hl.ask('gmail pass> ') {|inp| inp.echo = '*'}
options[:sendto]       = hl.ask('send to mail> ')

## daemonize
#if Process.respond_to? :daemon  # Ruby 1.9
#  Process.daemon
#else                            # Ruby 1.8
#  require 'webrick'
#  WEBrick::Daemon.start
#end

# initialize rreplizer
rreplizer = Rreplizer::Reply.new(options)
loop do
  begin
    rreplizer.get
    rreplizer.send_mail if rreplizer.new_replies?
    sleep 300
    rreplizer.fetch_mail
  rescue => e
    logger.error(e.backtrace.join("\n"))
    sleep 120
  end
end
