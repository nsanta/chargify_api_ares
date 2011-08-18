# Chargify API Wrapper using ActiveResource.
#
begin
  require 'active_resource'
rescue LoadError
  begin
    require 'rubygems'
    require 'active_resource'
  rescue LoadError
    abort <<-ERROR
The 'activeresource' library could not be loaded. If you have RubyGems 
installed you can install ActiveResource by doing "gem install activeresource".
ERROR
  end
end


# Version check
module Chargify
  ARES_VERSIONS = ['2.3.4', '2.3.5', '2.3.6', '2.3.7' , '2.3.8' , '2.3.10']
end
require 'active_resource/version'
unless Chargify::ARES_VERSIONS.include?(ActiveResource::VERSION::STRING)
  abort <<-ERROR
    ActiveResource version #{Chargify::ARES_VERSIONS.join(' or ')} is required.
  ERROR
end

# Patch ActiveResource version 2.3.4
if ActiveResource::VERSION::STRING == '2.3.4'
  module ActiveResource
    class Base
      def save
        save_without_validation
        true
      rescue ResourceInvalid => error
        case error.response['Content-Type']
        when /application\/xml/
          errors.from_xml(error.response.body)
        when /application\/json/
          errors.from_json(error.response.body)
        end
        false
      end
    end
  end
end


module Chargify
  
  class << self
    attr_accessor :subdomain, :api_key, :site, :format
    
    def configure
      yield self
      
      Base.user      = api_key
      Base.password  = 'X'
      
      if site.blank?
        Base.site                     = "https://#{subdomain}.chargify.com"
        Subscription::Component.site = 
          Subscription::Migration.site = 
          "https://#{subdomain}.chargify.com/subscriptions/:subscription_id"
      else
        Base.site                     = site
        Subscription::Component.site = 
          Subscription::Migration.site =
          site + "/subscriptions/:subscription_id"
      end
    end
  end
  
  class Base < ActiveResource::Base
    class << self
      def element_name
        name.split(/::/).last.underscore
      end
    end
    
    def to_xml(options = {})
      options.merge!(:dasherize => false)
      super
    end
  end
  
  class Customer < Base
    def self.find_by_reference(reference)
      Customer.new get(:lookup, :reference => reference)
    end
  end
  
  class Subscription < Base
    def self.find_by_customer_reference(reference)
      customer = Customer.find_by_reference(reference)
      find(:first, :params => {:customer_id => customer.id}) 
    end
    
    # Strip off nested attributes of associations before saving, or type-mismatch errors will occur
    def save
      self.attributes.delete('customer')
      self.attributes.delete('product')
      self.attributes.delete('credit_card')
      super
    end
    
    def cancel
      destroy
    end
    
    def component(id)
      begin
        return Component.find(id, :params => {:subscription_id => self.id})
      rescue  ActiveResource::ResourceNotFound
        return nil
      end
    end
    
    def components(params = {})
      params.merge!({:subscription_id => self.id})
      Component.find(:all, :params => params)
    end
    
    # Perform a one-time charge on an existing subscription.
    # For more information, please see the one-time charge API docs available 
    # at: http://support.chargify.com/faqs/api/api-charges
    def charge(attrs = {})
      post :charges, :charge => attrs
    end
    
    class Component < Base
      # All Subscription Components are considered already existing records, but the id isn't used
      def id
        self.component_id
      end
    end
    
    class Migration < Base
    end
    
  end

  class Product < Base
    def self.find_by_handle(handle)
      Product.new get(:lookup, :handle => handle)
    end
  end
  
  class ProductFamily < Base
    
    
    def coupons
      Coupon.find(:all , :params => {:product_family_id => self.id})
    end
    
    def coupon (coupon_id)
      begin
        return Coupon.find(coupon_id , :params => {:product_family_id => self.id})
      rescue  ActiveResource::ResourceNotFound
        return nil
      end
    end
    
    
    class Coupon < Base
    end 
  end
    
   
    
  class Usage < Base
    def subscription_id=(i)
      self.prefix_options[:subscription_id] = i
    end
    def component_id=(i)
      self.prefix_options[:component_id] = i
    end    
  end
  
  class Component < Base
  end
end
