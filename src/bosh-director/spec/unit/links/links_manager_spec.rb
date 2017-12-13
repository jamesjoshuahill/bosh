require 'spec_helper'

describe Bosh::Director::Links::LinksManager do
  subject { Bosh::Director::Links::LinksManager.new }

  describe '#find_or_create_provider' do
    let(:deployment_model) do
      Bosh::Director::Models::Deployment.new(
        name: 'test_deployment',
      ).save
    end

    before do
      # A Control provider
      Bosh::Director::Models::LinkProvider.new(
        deployment: deployment_model,
        instance_group: 'control_instance_group',
        name: 'control_link_name',
        owner_object_name: 'control_owner_object_name',
        owner_object_type: 'control_owner_object_type',
        link_provider_definition_name: 'control_link_provider_definition_name',
        link_provider_definition_type: 'control_link_provider_definition_type',
        content: 'control_content',
        consumable: true,
        shared: false,
      ).save
    end

    it 'adds links provider with correct default parameters' do
      expected_provider = Bosh::Director::Models::LinkProvider.new(
        deployment: deployment_model,
        instance_group: 'my_instance_group',
        name: 'my_link_name',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type',
        link_provider_definition_name: 'my_link_provider_definition_name',
        link_provider_definition_type: 'my_link_provider_definition_type',
        content: 'my_content',
        consumable: true,
        shared: false,
      ).save

      actual_provider = subject.find_or_create_provider(
        deployment_model: deployment_model,
        instance_group_name: 'my_instance_group',
        name: 'my_link_name',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type',
        link_provider_definition_name: 'my_link_provider_definition_name',
        link_provider_definition_type: 'my_link_provider_definition_type',
        content: 'my_content',
      )

      expect(actual_provider).to eq(expected_provider)
    end

    it 'adds links provider with correct NON default parameters' do
      expected_provider = Bosh::Director::Models::LinkProvider.new(
        deployment: deployment_model,
        instance_group: 'my_instance_group',
        name: 'my_link_name',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type',
        link_provider_definition_name: 'my_link_provider_definition_name',
        link_provider_definition_type: 'my_link_provider_definition_type',
        content: 'my_content',
        consumable: false,
        shared: true,
      ).save

      actual_provider = subject.find_or_create_provider(
        deployment_model: deployment_model,
        instance_group_name: 'my_instance_group',
        name: 'my_link_name',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type',
        link_provider_definition_name: 'my_link_provider_definition_name',
        link_provider_definition_type: 'my_link_provider_definition_type',
        content: 'my_content',
        options: {consumable: false, shared: true}
      )

      expect(actual_provider).to eq(expected_provider)
    end

    it 'creates a new provider if it does NOT already exist' do
      added_provider = subject.find_or_create_provider(
        deployment_model: deployment_model,
        instance_group_name: 'new_instance_group',
        name: 'new_link_name',
        owner_object_name: 'new_owner_object_name',
        owner_object_type: 'new_owner_object_type',
        link_provider_definition_name: 'new_link_provider_definition_name',
        link_provider_definition_type: 'new_link_provider_definition_type',
        content: 'new_content',
        options: {consumable: false, shared: true}
      )

      expected_provider = Bosh::Director::Models::LinkProvider.find(
        deployment: deployment_model,
        instance_group: 'new_instance_group',
        name: 'new_link_name',
        owner_object_name: 'new_owner_object_name',
        owner_object_type: 'new_owner_object_type',
        link_provider_definition_name: 'new_link_provider_definition_name',
        link_provider_definition_type: 'new_link_provider_definition_type',
        content: 'new_content',
        consumable: false,
        shared: true,
      )

      expect(added_provider.name).to eq('new_link_name')
      expect(added_provider).to eq(expected_provider)
    end
  end

  describe '#find_or_create_consumer' do
    let(:deployment_model) do
      Bosh::Director::Models::Deployment.new(
        name: 'test_deployment',
      ).save
    end

    before do
      # A Control Consumer
      Bosh::Director::Models::LinkConsumer.new(
        deployment: deployment_model,
        instance_group: 'control_instance_group',
        owner_object_name: 'control_owner_object_name',
        owner_object_type: 'control_owner_object_type'
      ).save
    end

    it 'finds the consumer if it exists' do
      expected_consumer = Bosh::Director::Models::LinkConsumer.new(
        deployment: deployment_model,
        instance_group: 'my_instance_group',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type'
      ).save

      actual_consumer = subject.find_or_create_consumer(
        deployment_model: deployment_model,
        instance_group_name: 'my_instance_group',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type',
      )

      expect(actual_consumer).to eq(expected_consumer)
    end

    it 'creates a new sonsumer if it does NOT already exist' do
      actual_consumer = subject.find_or_create_consumer(
        deployment_model: deployment_model,
        instance_group_name: 'my_instance_group',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type',
      )

      expected_consumer = Bosh::Director::Models::LinkConsumer.find(
        deployment: deployment_model,
        instance_group: 'my_instance_group',
        owner_object_name: 'my_owner_object_name',
        owner_object_type: 'my_owner_object_type',
      )

      expect(actual_consumer.owner_object_name).to eq('my_owner_object_name')
      expect(actual_consumer).to eq(expected_consumer)
    end
  end
end