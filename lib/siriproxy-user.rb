require 'mysql'

class SiriProxyUser
  attr_accessor :nickname

  def initialize(nickname)
    @nickname = nickname
    hostname = '...'
    username = '...'
    password = '...'
    database = '...'
    @my = Mysql.new(hostname, username, password, database)
    # TODO: Prevent SQL injection
    @info = @my.fetch_hash("select * from clients where nickname='#{nickname}'")
  end

  def valid?
    !@info.nil?
  end

  def torrentleech
    {
      :login =>  @info['tl_login'],
      :password => @info['tl_password'],
      :http => Net::HTTP.new('torrentleech.org')
    }
  end

  def utorrent
    {
      :host => @info['utorrent_host'],
      :login => @info['utorrent_login'],
      :password => @info['utorrent_password']
    }
  end
end
