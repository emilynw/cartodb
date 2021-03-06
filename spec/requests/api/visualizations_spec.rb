# encoding: utf-8
require 'sequel'
require 'rack/test'
require 'json'
require 'uri'
require_relative '../../spec_helper'
require_relative '../../../app/controllers/api/json/visualizations_controller'
require_relative '../../../services/data-repository/backend/sequel'
require 'helpers/unique_names_helper'

# INFO: THIS TEST SUITE SHOULD NOT GET NEW TESTS. In order to test visualization controller
# add the specs to ./spec/requests/api/json/visualizations_controller_shared_examples.rb instead.
# You can then run it with ./spec/requests/api/json/visualizations_controller_specs.rb and
# ./spec/requests/carto/api/visualizations_controller_specs.rb.
describe Api::Json::VisualizationsController do
  include UniqueNamesHelper
  include Rack::Test::Methods
  include DataRepository

  before(:all) do
    CartoDB::Varnish.any_instance.stubs(:send_command).returns(true)
    @user = create_user(
      username: 'test',
      email:    'client@example.com',
      password: 'clientex',
      private_tables_enabled: true,
      private_maps_enabled: true
    )
    @api_key = @user.api_key
  end

  before(:each) do
    CartoDB::Varnish.any_instance.stubs(:send_command).returns(true)
    bypass_named_maps_requests

    begin
      delete_user_data @user
    rescue => exception
      # Silence named maps problems only here upon data cleaning, not in specs
      raise unless exception.class.to_s == 'CartoDB::NamedMapsWrapper::HTTPResponseError'
    end

    @headers = {
      'CONTENT_TYPE' => 'application/json'
    }
    host! 'test.localhost.lan'
  end

  after(:all) do
    bypass_named_maps
    @user.destroy
  end

  describe 'POST /api/v1/viz' do
    it 'creates a visualization' do
      payload = factory.merge(type: 'table')

      post "/api/v1/viz?api_key=#{@api_key}", payload.to_json, @headers

      last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response.fetch('tags')        .should == payload.fetch(:tags)
      response.fetch('map_id')      .should == payload.fetch(:map_id)
      response.fetch('description') .should == payload.fetch(:description)

      id = response.fetch('id')

      get "/api/v1/viz/#{id}?api_key=#{@api_key}", {}, @headers
      last_response.status.should == 200

      response = JSON.parse(last_response.body)
      response.fetch('name')        .should_not == nil
      response.fetch('tags')        .should_not == payload.fetch(:tags).to_json
      response.keys.should_not include 'related'
    end

    it 'creates a visualization from a source_visualization_id' do
      table                 = table_factory
      source_visualization  = table.fetch('table_visualization')

      payload = { source_visualization_id: source_visualization.fetch('id') }

      post "/api/v1/viz?api_key=#{@api_key}", payload.to_json, @headers
      last_response.status.should == 200
      response = JSON.parse(last_response.body)
      id = response.fetch('id')

      CartoDB::Visualization::Member.new(id: id).fetch.derived?.should be_true
    end

    it 'creates a private visualization from a private table' do
      table1 = table_factory(privacy: 0)
      source_visualization_id = table1.fetch('table_visualization').fetch('id')
      payload = { source_visualization_id: source_visualization_id }

      post "/api/v1/viz?api_key=#{@api_key}", payload.to_json, @headers
      last_response.status.should == 200

      visualization = JSON.parse(last_response.body)
      visualization.fetch('privacy').should == 'PRIVATE'
    end

    it 'creates a private visualization if any table in the list is private' do
      table3 = table_factory(privacy: 0)

      payload = {
        name: 'new visualization',
        tables: [table3.fetch('name')]
      }

      post "/api/v1/viz?api_key=#{@api_key}", payload.to_json, @headers
      last_response.status.should == 200

      visualization = JSON.parse(last_response.body)
      visualization.fetch('privacy').should == 'PRIVATE'
    end

    it 'creates a private visualization if any table in the list is private' do
      table1 = table_factory
      table2 = table_factory
      table3 = table_factory(privacy: 0)

      payload = {
        name: 'new visualization',
        tables: [
          table1.fetch('name'),
          table2.fetch('name'),
          table3.fetch('name')
        ],
        privacy: 'public'
      }

      post "/api/v1/viz?api_key=#{@api_key}", payload.to_json, @headers
      last_response.status.should == 200

      visualization = JSON.parse(last_response.body)
      visualization.fetch('privacy').should == 'PRIVATE'
    end

    it 'assigns a generated name if name taken' do
      table               = table_factory
      visualization       = table.fetch('table_visualization')
      visualization_name  = visualization.fetch('name')

      payload = {
        source_visualization_id:  visualization.fetch('id'),
        name:                     visualization_name
      }

      post "/api/v1/viz?api_key=#{@api_key}", payload.to_json, @headers
      last_response.status.should == 200

      response = JSON.parse(last_response.body)
      response.fetch('name').should =~ /#{visualization_name} 1/
    end
  end # POST /api/v1/viz

  describe 'PUT /api/v1/viz/:id' do
    it 'updates an existing visualization' do
      payload = factory
      post "/api/v1/viz?api_key=#{@api_key}", payload.to_json, @headers

      response = JSON.parse(last_response.body)
      id = response.fetch('id')

      response.fetch('tags').should == ['foo', 'bar']

      put "/api/v1/viz/#{id}?api_key=#{@api_key}", { name: 'changed', tags: [], id: id }.to_json, @headers
      last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response.fetch('name').should == 'changed'
      response.fetch('tags').should == []
    end

    it 'updates the table in a table visualization', now: true do
      table_attributes = table_factory
      id = table_attributes.fetch('table_visualization').fetch('id')

      Delorean.jump(1.minute)
      put "/api/v1/viz/#{id}?api_key=#{@api_key}", { name: 'changed name', id: id }.to_json, @headers
      Delorean.back_to_the_present
      last_response.status.should == 200
      response = JSON.parse(last_response.body)

      response.fetch('table').fetch('updated_at').should_not == table_attributes.fetch('updated_at')
    end

    it 'returns a sanitized name' do
      table_attributes = table_factory
      id = table_attributes.fetch('table_visualization').fetch('id')

      put "/api/v1/viz/#{id}?api_key=#{@api_key}", { name: 'changed name', id: id }.to_json, @headers
      last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response.fetch('name').should == 'changed_name'

      get "/api/v1/viz/#{id}?api_key=#{@api_key}", {}, @headers
      response = JSON.parse(last_response.body)
      response.fetch('name').should == 'changed_name'
    end
  end # PUT /api/v1/viz/:id

  describe 'DELETE /api/v1/viz/:id' do
    it 'deletes the visualization' do
      payload = factory
      post "/api/v1/viz?api_key=#{@api_key}",
        payload.to_json, @headers

      id = JSON.parse(last_response.body).fetch('id')
      get "/api/v1/viz/#{id}?api_key=#{@api_key}", {}, @headers
      last_response.status.should == 200

      delete "/api/v1/viz/#{id}?api_key=#{@api_key}", {}, @headers
      last_response.status.should == 204
      last_response.body.should be_empty

      get "/api/v1/viz/#{id}?api_key=#{@api_key}", {}, @headers
      last_response.status.should == 404
    end

    it 'deletes the associated table' do
      table_attributes = table_factory
      table_id = table_attributes.fetch('id')

      get "/api/v1/tables/#{table_id}?api_key=#{@api_key}", {}, @headers
      last_response.status.should == 200
      table             = JSON.parse(last_response.body)
      visualization_id  = table.fetch('table_visualization').fetch('id')

      delete "/api/v1/viz/#{visualization_id}?api_key=#{@api_key}", {}, @headers
      last_response.status.should == 204

      get "/api/v1/tables/#{table_id}?api_key=#{@api_key}", {}, @headers
      last_response.status.should == 404
    end
  end # DELETE /api/v1/viz/:id

  describe '#slides_sorting' do
    it 'checks proper working of prev/next' do
      bypass_named_maps

      map_id = ::Map.create(user_id: @user.id).id

      post api_v1_visualizations_create_url(user_domain: @user.username, api_key: @api_key),
           factory(
             name: 'PARENT',
             type: CartoDB::Visualization::Member::TYPE_DERIVED
           ).to_json, @headers
      body = JSON.parse(last_response.body)
      parent_vis_id = body.fetch('id')

      # A
      post api_v1_visualizations_create_url(user_domain: @user.username, api_key: @api_key),
           {
             name: 'A',
             type: CartoDB::Visualization::Member::TYPE_SLIDE,
             parent_id: parent_vis_id,
             map_id: map_id
           }.to_json, @headers
      body = JSON.parse(last_response.body)
      vis_a_id = body.fetch('id')
      body.fetch('prev_id').should eq nil
      body.fetch('next_id').should eq nil

      # standalone
      post api_v1_visualizations_create_url(user_domain: @user.username, api_key: @api_key),
           factory(name: 'standalone').to_json, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq nil
      body.fetch('next_id').should eq nil

      # A -> B
      post api_v1_visualizations_create_url(user_domain: @user.username, api_key: @api_key),
           {
             name: 'B',
             type: CartoDB::Visualization::Member::TYPE_SLIDE,
             parent_id: parent_vis_id,
             map_id: map_id,
             prev_id: vis_a_id
           }.to_json, @headers
      body = JSON.parse(last_response.body)
      vis_b_id = body.fetch('id')
      body.fetch('prev_id').should eq vis_a_id
      body.fetch('next_id').should eq nil

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_a_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq nil
      body.fetch('next_id').should eq vis_b_id
      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_b_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_a_id
      body.fetch('next_id').should eq nil

      # C -> A -> B
      post api_v1_visualizations_create_url(user_domain: @user.username, api_key: @api_key),
           {
             name: 'C',
             type: CartoDB::Visualization::Member::TYPE_SLIDE,
             parent_id: parent_vis_id,
             map_id: map_id,
             next_id: vis_a_id
           }.to_json, @headers
      body = JSON.parse(last_response.body)
      vis_c_id = body.fetch('id')
      body.fetch('prev_id').should eq nil
      body.fetch('next_id').should eq vis_a_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_c_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq nil
      body.fetch('next_id').should eq vis_a_id
      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_a_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_c_id
      body.fetch('next_id').should eq vis_b_id
      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_b_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_a_id
      body.fetch('next_id').should eq nil

      # C -> D -> A -> B
      post api_v1_visualizations_create_url(user_domain: @user.username, api_key: @api_key),
           {
             name: 'D',
             type: CartoDB::Visualization::Member::TYPE_SLIDE,
             parent_id: parent_vis_id,
             map_id: map_id,
             prev_id: vis_c_id,
             next_id: vis_a_id
           }.to_json, @headers
      body = JSON.parse(last_response.body)
      vis_d_id = body.fetch('id')
      body.fetch('prev_id').should eq vis_c_id
      body.fetch('next_id').should eq vis_a_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_c_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq nil
      body.fetch('next_id').should eq vis_d_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_d_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_c_id
      body.fetch('next_id').should eq vis_a_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_a_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_d_id
      body.fetch('next_id').should eq vis_b_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_b_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_a_id
      body.fetch('next_id').should eq nil

      # C -> A -> B -> D
      put api_v1_visualizations_set_next_id_url(user_domain: @user.username, api_key: @api_key, id: vis_d_id),
          { next_id: nil }.to_json, @headers
      last_response.status.should == 200

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_c_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq nil
      body.fetch('next_id').should eq vis_a_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_a_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_c_id
      body.fetch('next_id').should eq vis_b_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_b_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_a_id
      body.fetch('next_id').should eq vis_d_id

      get api_v1_visualizations_show_url(user_domain: @user.username, api_key: @api_key, id: vis_d_id),
          {}, @headers
      body = JSON.parse(last_response.body)
      body.fetch('prev_id').should eq vis_b_id
      body.fetch('next_id').should eq nil
    end
  end

  # Visualizations are always created with default_privacy
  def factory(attributes={})
    {
      name:                     attributes.fetch(:name, unique_name('viz')),
      tags:                     attributes.fetch(:tags, ['foo', 'bar']),
      map_id:                   attributes.fetch(:map_id, ::Map.create(user_id: @user.id).id),
      description:              attributes.fetch(:description, 'bogus'),
      type:                     attributes.fetch(:type, 'derived'),
      privacy:                  attributes.fetch(:privacy, 'public'),
      source_visualization_id:  attributes.fetch(:source_visualization_id, nil),
      parent_id:                attributes.fetch(:parent_id, nil),
      locked:                   attributes.fetch(:locked, false),
      prev_id:                  attributes.fetch(:prev_id, nil),
      next_id:                  attributes.fetch(:next_id, nil)
    }
  end

  def table_factory(options={})
    privacy = options.fetch(:privacy, 1)

    name    = unique_name('table')
    payload = {
      name:         name,
      description:  "#{name} description"
    }
    post "/api/v1/tables?api_key=#{@api_key}", payload.to_json, @headers

    table_attributes  = JSON.parse(last_response.body)
    table_id          = table_attributes.fetch('table_visualization').fetch("id")

    put "/api/v1/viz/#{table_id}?api_key=#{@api_key}", { privacy: privacy }.to_json, @headers

    table_attributes
  end
end
