require 'rubygems'
require 'capcode'
require 'capcode/base/dm'

# Require Ceres libs
require './lib/feed.rb'

require 'pp'

Ceres::Feeds::Reader.new(20).start

# -- Modele -------------------------------------------------------------------

class Feed < Capcode::Base
  include Capcode::Resource
  
  property :id, Serial

  property :host, String
  property :url, String
  property :feed, String
  property :title, String
  property :description, Text
  property :active, String
  
  property :last_update, Date
  
  has n, :posts
end

class Post < Capcode::Base
  include Capcode::Resource
  property :id, Serial
  
  property :title, String
  property :content, Text
  property :date, Date
  property :url, String
  property :post_id, String
  
  belongs_to :feed
  
  def self.paginate( opts = {} )
    opts = {:page => 1, :per_page => 10, :order => :date.desc}.merge(opts)    
    
    order = opts.delete(:order) || []
    
    all = Post.all( :order => order )
    
    number_of_pages = all.count / opts[:per_page]
    number_of_pages = ((all.count - (number_of_pages * opts[:per_page])) > 0)?(number_of_pages+1):number_of_pages
    
    page = opts[:page]
    page = 1 if page < 1
    page = number_of_pages if page > number_of_pages
    page -= 1
    
    start = page*opts[:per_page]
    
    all[start, opts[:per_page]]
  end
end

class Moderator < Capcode::Base
  include Capcode::Resource
  property :id, Serial
  
  property :login, String
  property :realname, String
  property :password_hash, String
  property :password_salt, String
  
  def password=(pass)
    salt = [Array.new(6){rand(256).chr}.join].pack("m").chomp
    self.password_salt, self.password_hash = salt, Digest::SHA256.hexdigest( pass + salt )
  end

  def self.authenticate( login, password )
    user = Moderator.first( :login => login )
    if user.blank? || Digest::SHA256.hexdigest( password + user.password_salt ) != user.password_hash
      return nil
    end
    return user
  end
end

# -- Controller ---------------------------------------------------------------

module Capcode
  set :erb, "views"
  set :static, "static"
  
  before_filter :check_login
  before_filter :user_logged, :only => [:Administration]
  
  def check_login
    if session[:user]
      @user = Moderator.get(session[:user])
    else
      @user = nil
    end
    nil
  end
  
  def user_logged
    if session[:user]
      nil
    else
      redirect Capcode::Login
    end
  end
  
  class Index < Route '/'
    def get
      @posts = Post.paginate( )
      render :erb => :index
    end
  end
  
  class Style < Route '/style'
    def get
      render :static => "style.css"
    end
  end
  
  class ProposeFeed < Route '/propose'
    def get
      @alternates = nil
      render :erb => :propose
    end
    
    def post
      @alternates = Ceres::Feeds.fromURL( params['url'] )
      render :erb => :propose
    end
  end
  
  class SubmitFeed < Route '/propose/submit'
    def get
      redirect ProposeFeed
    end
    
    def post
      feed = Feed.new(params)
      if feed.save
        redirect Index 
      else
        @error = true
        render :erb => :proposal
      end
    end
  end
  
  class Login < Route '/login'
    def get
      if session[:user]
        redirect Index
      else
        render :erb => :login
      end
    end
    
    def post
      user = Moderator.authenticate( params['login'], params['password'] )
      if user
        session[:user] = user.id
      end
      
      redirect Index
    end
  end
  
  class Logout < Route '/logout'
    def get
      session.delete(:user)
      redirect Index
    end
  end
  
  class Administration < Route '/admin'
    def get
      @feeds = Feed.all
      @users = Moderator.all

      render :erb => :administration
    end
  end
  
  class Activate < Route '/activate/(.*)'
    def get( id )
      feed = Feed.get(id.to_i)
      feed.active = "yes"
      feed.save
      redirect Administration
    end
  end
  
  class Deactivate < Route '/deactivate/(.*)'
    def get( id )
      feed = Feed.get(id.to_i)
      feed.active = nil
      feed.save
      redirect Administration
    end
  end
  
end

Capcode.run( :port => 3001, :host => "localhost", :db_config => "ceres.yml" ) do 
  if Moderator.all.count <= 0
    m = Moderator.new( :login => "admin", :realname => "Admin")
    m.password = "admin"
    m.save
  end
end