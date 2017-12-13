module Bosh::Director::Links
  class LinksManager

    def find_or_create_provider(
      deployment_model:,
      instance_group_name:,
      name:,
      owner_object_name:,
      owner_object_type:,
      link_provider_definition_name:,
      link_provider_definition_type:,
      content:,
      options: {}
    )
      Bosh::Director::Models::LinkProvider.find_or_create(
        deployment: deployment_model,
        instance_group: instance_group_name,
        name: name,
        owner_object_name: owner_object_name,
        owner_object_type: owner_object_type,
        link_provider_definition_name: link_provider_definition_name,
        link_provider_definition_type: link_provider_definition_type,
        content: content,
        consumable: options.fetch(:consumable, true),
        shared: options.fetch(:shared, false),
      )
    end


    def find_or_create_consumer(
      deployment_model:,
      instance_group_name:,
      owner_object_name:,
      owner_object_type:
    )
      Bosh::Director::Models::LinkConsumer.find_or_create(
        deployment: deployment_model,
        instance_group: instance_group_name,
        owner_object_name: owner_object_name,
        owner_object_type: owner_object_type,
      )
    end
  end
end