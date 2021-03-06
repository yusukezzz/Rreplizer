require 'net/http'
require 'net/smtp'
require 'net/pop'
require 'json'
require 'uri'
require 'kconv'
Net::HTTP.version_1_2

module Rreplizer
  # manage twitter and gmail account
  class Account
    require 'tlsmail'

    def initialize(options = {})
      @twitter_id = options[:twitter_id]
      @twitter_pass = options[:twitter_pass]
      @gmail_id = options[:gmail_id]
      @gmail_pass = options[:gmail_pass]
      @sendto = options[:sendto]
    end

    attr_reader :sendto

    # http access
    def connection(uri, method = :get)
      begin
        uri = URI.parse(uri)
        http = Net::HTTP.new(uri.host)
        req = nil
        case method
        when :get
          req = Net::HTTP::Get.new(uri.path+'?'+uri.query.to_s)
        when :post
          req = Net::HTTP::Post.new(uri.path)
          req.body = uri.query
        end
        req.basic_auth(@twitter_id.to_s, @twitter_pass.to_s)
        res = http.request(req)
        return res
      rescue
        sleep 60
        retry
      end
    end

    # tls smtp send mail
    def send_mail(mail)
      mail.from = @gmail_id
      mail.to = @sendto
      result = nil
      Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
      Net::SMTP.start('smtp.gmail.com', 587, 'localhost.localdomain',
                      @gmail_id.to_s + '@gmail.com', @gmail_pass.to_s, 'plain') do |smtp|
        result = smtp.send_mail(mail.encoded, mail.from, mail.to)
      end
      return result
    end

    # ssl pop3 get mails
    def fetch_mail
      mails = []
      Net::POP3.enable_ssl(OpenSSL::SSL::VERIFY_NONE)
      Net::POP3.delete_all('pop.gmail.com', 995, @gmail_id.to_s, @gmail_pass.to_s) do |m|
        mails << m.pop
      end
      return mails
    end
  end

  # manage twitter replies(get and post)
  class Reply
    require 'tmail'

    def initialize(options = {})
      @account = Rreplizer::Account.new(options)
      @since_id = self.get(1) # get latest reply id
      @replies = []
    end

    # return true if recieve new replies(newer than @since_id)
    def new_replies?
      return (@replies.length > 0) ? true : false
    end

    # get latest replies
    def get(count = 20)
      uri = "http://twitter.com/statuses/mentions.json?count=#{count.to_s}"
      (uri << "&since_id=#{@since_id.to_s}") if @since_id
      res = @account.connection(uri)
      @replies = JSON.parse(res.body) if res.code == '200'
      @since_id = @replies[0]['id'] if self.new_replies?
      return @since_id
    end

    # recieve email
    def fetch_mail
      mails = @account.fetch_mail
      mails.each do |m|
        mail = TMail::Mail.parse(m)
        if mail.subject && mail.body
          subject = Array.new(mail.subject.toutf8.split(':'))
          users = Array.new(subject[subject.length - 2].split(','))
          in_reply_to = subject[subject.length - 1].to_s
          tweet = mail.body.to_s
          self.post(users, tweet, in_reply_to) if mail.from.to_s == @account.sendto.to_s
        end
      end
    end

    # do Account.send_mail
    def send_mail
      result = nil
      mails = self.to_mail
      mails.each do |m|
        result = @account.send_mail(m)
      end
      @replies = [] if result =~ /OK/
    end

  protected
    # reply post to twitter
    def post(users, tweet, in_reply_to)
      if tweet
        update = "#{users.map{|u| "@#{u}"}.join(' ')} #{tweet.toutf8}"
        uri = "http://twitter.com/statuses/update.json?status=#{URI.encode(update)}&in_reply_to_status_id=#{in_reply_to.to_s}"
        res = @account.connection(uri, :post)
      end
    end

    # return latest reply users
    def get_users(replies)
      users = []
      replies.each do |r|
        users << r['user']['screen_name']
      end
      return users.uniq
    end

    # convert replies to mail
    def to_mail
      @replies.reverse!
      mails = []
      # replies divide by in_reply_to_status_id
      for i in @replies.map{|r| r['in_reply_to_status_id'] }.uniq
        to_mail_replies = []
        @replies.each do |r|
          to_mail_replies << r if r['in_reply_to_status_id'] == i
        end
        # to mail
        subject = 'Reply from:' + get_users(to_mail_replies).join(',') + ":#{to_mail_replies[0]['id'].to_s}"
        body = to_mail_replies.map{|tmr| "#{tmr['text']} from #{tmr['user']['screen_name']}"}.join("\r\n")
        mail = TMail::Mail.new
        mail.subject = subject.toutf8
        mail.body = body.toutf8
        mail.date = Time.now
        mail.mime_version = '1.0'
        mail.set_content_type 'text', 'plain', {'charset' => 'utf-8'}
        mails << mail
      end
      return mails
    end
  end
end
