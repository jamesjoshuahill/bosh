Sequel.migration do
  up do

    create_table :link_providers do
      primary_key :id
      foreign_key :deployment_id, :deployments, :null => false, :on_delete => :cascade
      String :name, :null => false
      String :type, :null => false
      String :instance_group, :null => false
    end

    create_table :link_providers_intents do
      primary_key :id
      foreign_key :provider_id, :link_providers, :null => false, :on_delete => :cascade
      String :name, :null => false
      String :type, :null => false
      String :alias, :null => false
      String :content, :null => false # rely on networks
      Boolean :shared, :null => false
      Boolean :consumable, :null => false
    end

    create_table :link_consumers do
      primary_key :id
      foreign_key :deployment_id, :deployments, :on_delete => :cascade
      String :instance_group
      String :name, :null => false
      String :type, :null => false
    end

    create_table :link_consumers_intents do
      primary_key :id
      foreign_key :link_consumer_id, :link_consumers, :on_delete => :cascade
      String :name, :null => false
      String :type, :null => false
      Boolean :optional, :null => false
      Boolean :blocked, :null => false # intentially blocking the consumption of the link, consume: nil
      # String :metadata, :null => false # put extra json object that has some flags, ip addresses true or false, or any other potential thing
    end

    create_table :links do
      primary_key :id
      foreign_key :link_provider_intent_id, :link_providers_intents, :on_delete => :set_null
      foreign_key :link_consumer_intent_id, :link_consumers_intents, :on_delete => :cascade, :null => false
      String :name, :null => false
      String :link_content
      Time :created_at
    end

    create_table :instances_links do
      foreign_key :link_id, :links, :on_delete => :cascade, :null => false
      foreign_key :instance_id, :instances, :on_delete => :cascade, :null => false
      unique [:instance_id, :link_id]
    end

    if [:mysql, :mysql2].include? adapter_scheme
      set_column_type :link_providers_intents, :content, 'longtext'
      set_column_type :links, :link_content, 'longtext'
    end

    self[:deployments].each do |deployment|
      link_spec_json = JSON.parse(deployment[:link_spec_json] || '{}')
      link_spec_json.each do |instance_group_name, provider_jobs|
        provider_jobs.each do |provider_job_name, link_names|
          provider_id = self[:link_providers].insert({
            deployment_id: deployment[:id],
            name: provider_job_name,
            type: 'job',
            instance_group: instance_group_name,
          })

          link_names.each do |link_name, link_types|
            link_types.each do |link_type, content|
              self[:link_providers_intents].insert(
                {
                  provider_id: provider_id,
                  name: link_name,
                  type: link_type,
                  alias: link_name,
                  shared: true,
                  consumable: true,
                  content: content.to_json,
                }
              )
            end
          end
        end
      end
    end

    links_to_migrate = {}

    Struct.new('LinkKey', :deployment_id, :instance_group, :job, :link_name) unless defined?(Struct::LinkKey)
    Struct.new('LinkDetail', :link_id, :content) unless defined?(Struct::LinkDetail)

    self[:instances].each do |instance|
      spec_json = JSON.parse(instance[:spec_json] || '{}')
      links = spec_json['links'] || {}
      links.each do |job_name, consumed_links|
        consumer = self[:link_consumers].where(deployment_id: instance[:deployment_id], instance_group: instance[:job], name: job_name).first

        if consumer
          consumer_id = consumer[:id]
        else
          consumer_id = self[:link_consumers].insert(
            {
              deployment_id: instance[:deployment_id],
              instance_group: instance[:job],
              name: job_name,
              type: 'job'
            }
          )
        end

        consumed_links.each do |link_name, link_data|
          link_key = Struct::LinkKey.new(instance[:deployment_id], instance[:job], job_name, link_name)

          # since we can go through multiple instances
          link_details = links_to_migrate[link_key] || []
          link_detail = link_details.find do |link_detail|
            link_detail.content == link_data
          end

          link_consumer_intent = self[:link_consumers_intents].where(link_consumer_id: consumer_id, name: link_name).first

          if link_consumer_intent
            link_consumer_intent_id = link_consumer_intent[:id]
          else
            link_consumer_intent_id = self[:link_consumers_intents].insert(
              {
                link_consumer_id: consumer_id,
                name: link_name,
                type: 'undefined-migration',
                optional: false,
                blocked: false
              }
            )
          end

          unless link_detail
            link_id = self[:links].insert(
              {
                name: link_name,
                link_provider_intent_id: nil,
                link_consumer_intent_id: link_consumer_intent_id,
                link_content: link_data.to_json,
                created_at: Time.now,
              }
            )
            link_detail = Struct::LinkDetail.new(link_id, link_data)

            link_details << link_detail
            links_to_migrate[link_key] = link_details
          end

          self[:instances_links] << {
            link_id: link_detail.link_id,
            instance_id: instance[:id]
          }
        end
      end
    end
  end
end
