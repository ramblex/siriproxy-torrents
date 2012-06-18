require 'siri_objects'
require 'pp'
require 'hpricot'
require 'net/http'
require 'net/http/post/multipart'
require_relative './siriproxy_user'

class SiriProxy::Plugin::Torrents < SiriProxy::Plugin
  # Siri passes small numbers as words.
  # We use an array to convert them back to integers
  @@numbers = %w(zero one two three four five six seven eight nine ten)

  def initialize(config)
    # TODO: Not sure where nickname actually comes from or when it gets set
    @user = SiriProxyUser.new(config['nickname'])
    report_no_account unless @user.valid?
  end

  def report_no_account
    say "I am unable to find your account. Please check your nickname in your contacts card"
    # TODO: Raise something?
  end

  def get_cookies_from_response(response)
    cookies = response.to_hash['set-cookie']
    return '' if cookies.nil?
    cookies = cookies.map{|i| i.split(';')[0].split '='}.flatten
    cookies = Hash[*cookies].reject{|k, v| v == 'deleted'}
    cookies.map{|k, v| "#{k}=#{v}"}.join '; '
  end

  def torrentleech_login
    request = Net::HTTP::Post.new '/user/account/login'
    request.set_form_data({'username' => @user.torrentleech[:login], 'password' => @user.torrentleech[:password]})
    response = @user.torrentleech[:http].request request
    cookies = get_cookies_from_response response
    @user.torrentleech[:cookies] = cookies unless cookies.empty?
  end

  def torrentleech_search(query)
    torrentleech_login if @user.torrentleech[:cookies].nil?
    request = Net::HTTP::Get.new "/torrents/browse/index/query/#{query}/order/desc/orderby/seeders"
    request['Cookie'] = @user.torrentleech[:cookies]
    response = @user.torrentleech[:http].request request
    cookies = get_cookies_from_response response
    @user.torrentleech[:cookies] = cookies unless cookies.empty?
    html = Hpricot(response.body)
    results = []
    (html/'table#torrenttable/tbody/tr').each do |row|
        results << {
            title:    (row / 'td[2]/span.title/a').inner_text,
            href:     (row % 'td[3]/a')['href'],
            size:     (row / 'td[5]').inner_text,
            seeders:  (row / 'td[7]').inner_text,
            leechers: (row / 'td[8]').inner_text
        }
    end
    results
  end

  def utorrent_get_token
    uri = URI("http://#{@user.utorrent[:host]}/gui/token.html?t=#{Time.now.to_i}")
    request = Net::HTTP::Get.new uri.request_uri
    request.basic_auth @user.utorrent[:login], @user.utorrent[:password]

    response = Net::HTTP.start uri.hostname, uri.port do |http|
      http.request request
    end

    cookies = get_cookies_from_response response
    @user.utorrent[:cookies] = cookies unless cookies.empty?

    (Hpricot(response.body) % 'div').inner_text
  end

  def say_results(start = 0)
    @user.torrentleech[:results][start..start + 2].each_with_index do |result, i|
      say "#{result[:title]} (#{result[:size]}, #{result[:seeders]} seeders, #{result[:leechers]} leechers)", spoken: "#{i}. #{result[:title]}"
    end

    response = ask "Which one should i download?"

    if response =~ /(zero|one|two)/i
      match = @@numbers.index $1.downcase
      start_download start + match
    elsif response =~ /more/i
      say_results start + 3
    else
      say "Download cancelled"
    end
  end

  def start_download(id)
    result = @user.torrentleech[:results][id]

    request = Net::HTTP::Get.new result[:href]
    request['Cookie'] = @user.torrentleech[:cookies]
    response = @user.torrentleech[:http].request request

    cookies = get_cookies_from_response response
    @user.torrentleech[:cookies] = cookies unless cookies.empty?

    @user.utorrent[:token] = utorrent_get_token if @user.utorrent[:token].nil?

    uri = URI("http://#{@user.utorrent[:host]}/gui/")
    params = {token: @user.utorrent[:token], action: 'add-file', download_dir: 0, path: ''}
    uri.query = URI.encode_www_form(params)

    file = UploadIO.new StringIO.new(response.body), 'application/octet-stream', result[:href].split('/').last
    request = Net::HTTP::Post::Multipart.new uri.request_uri, torrent_file: file
    request.basic_auth @user.utorrent[:login], @user.utorrent[:password]
    request['Cookie'] = @user.utorrent[:cookies]

    response = Net::HTTP.start uri.hostname, uri.port do |http|
      http.request request
    end

    say "Downloading #{result[:title]} From TorrentLeech!"
  end

  listen_for /download (.*)/i do |name|
    @user.torrentleech[:results] = torrentleech_search name
    say_results
    request_completed
  end
end
