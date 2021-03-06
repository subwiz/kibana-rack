module Kibana
  module Rack
    # Rack application that serves Kibana and proxies requests to Elasticsearch
    class Web < Sinatra::Base
      register Sinatra::MultiRoute

      set :root, File.expand_path('../../../../web', __FILE__)
      set :public_folder, -> { "#{root}/assets" }
      set :views, -> { "#{root}/views" }

      set :elasticsearch_host, -> { Kibana.elasticsearch_host }
      set :elasticsearch_port, -> { Kibana.elasticsearch_port }
      set :kibana_dashboards_path, -> { Kibana.kibana_dashboards_path }
      set :kibana_default_route, -> { Kibana.kibana_default_route }
      set :kibana_index, -> { Kibana.kibana_index }

      helpers do
        def validate_kibana_index_name
          render_not_found unless params[:index] == settings.kibana_index
        end

        def account_index
          session[:account_dash]
        end  

        def patch_alias_response
          a = proxy_es_request
          unless a[2].nil?
            content_length = a[2].length
            a[2].gsub!(account_index,"freshlogs")
            headers = a[1]
            new_headers = headers
            new_headers[:content_length] = a[2].length.to_s
            a[1] = new_headers
          end
          a
        end

        def proxy
          es_host = settings.elasticsearch_host
          es_port = settings.elasticsearch_port
          @proxy ||= Faraday.new(url: "http://#{es_host}:#{es_port}")
        end

        def proxy_es_request
          request.body.rewind

          proxy_method = request.request_method.downcase.to_sym
          proxy_response = proxy.send(proxy_method) do |proxy_request|
            req_url = request.path_info.gsub("freshlogs",account_index)
            proxy_request.url(req_url)
            proxy_request.headers['Content-Type'] = 'application/json'
            proxy_request.params = env['rack.request.query_hash']
            proxy_request.body = request.body.read if [:post, :put].include?(proxy_method)
          end

          [proxy_response.status, proxy_response.headers, proxy_response.body]
        end

        def render_not_found
          halt(404, '<h1>Not Found</h1>')
        end
      end

      before do
        render_not_found if account_index.nil?
      end

      get '/' do
        erb :index
      end

      get '/config.js' do
        content_type 'application/javascript'
        erb :config
      end

      get(%r{/app/dashboards/([\w-]+)\.(js(on)?)}) do
        dashboard_name = params[:captures][0]
        dashboard_ext = params[:captures][1]
        dashboard_path = File.join(settings.kibana_dashboards_path, "#{dashboard_name}.#{dashboard_ext}")

        render_not_found unless File.exist?(dashboard_path)

        template = IO.read(dashboard_path)
        content_type "application/#{dashboard_ext}"
        erb template
      end

      route(:get, :post, '/_aliases') do
        patch_alias_response
      end

      route(:get, :post, '/_nodes') do
        proxy_es_request
      end

      route(:get, :post, '/:index/_aliases') do
        patch_alias_response
      end

      route(:get, :post, '/:index/_mapping') do
        proxy_es_request
      end

      route(:get, :post, '/:index/_search') do
        proxy_es_request
      end

      # route(:delete, :get, :post, :put, '/_aliases') do
      #   patch_alias_response
      # end

      # route(:delete, :get, :post, :put, '/_nodes') do
      #   proxy_es_request
      # end

      # route(:delete, :get, :post, :put, '/:index/_aliases') do
      #   patch_alias_response
      # end

      # route(:delete, :get, :post, :put, '/:index/_mapping') do
      #   proxy_es_request
      # end

      # route(:delete, :get, :post, :put, '/:index/_search') do
      #   proxy_es_request
      # end

      # route(:delete, :get, :post, :put, '/:index/temp') do
      #   validate_kibana_index_name
      #   proxy_es_request
      # end

      # route(:delete, :get, :post, :put, '/:index/temp/:name') do
      #   validate_kibana_index_name
      #   proxy_es_request
      # end

      # route(:delete, :get, :post, :put, '/:index/dashboard/:dashboard') do
      #   validate_kibana_index_name
      #   proxy_es_request
      # end
    end
  end
end