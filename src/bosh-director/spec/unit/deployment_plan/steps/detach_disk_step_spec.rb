require 'spec_helper'

module Bosh::Director
  module DeploymentPlan
    module Steps
      describe DetachDiskStep do
        subject(:step) { DetachDiskStep.new(disk) }

        let!(:vm) { Models::Vm.make(active: true, instance: instance) }
        let(:instance) { Models::Instance.make }
        let!(:disk) { Models::PersistentDisk.make(instance: instance, name: '') }
        let(:cloud_factory) { instance_double(CloudFactory) }
        let(:cloud) { Config.cloud }

        before do
          allow(CloudFactory).to receive(:create_with_latest_configs).and_return(cloud_factory)
          allow(cloud_factory).to receive(:get).with(disk&.cpi).once.and_return(cloud)
          allow(cloud).to receive(:detach_disk)
        end

        it 'calls out to cpi associated with disk to detach disk' do
          expect(cloud).to receive(:detach_disk).with(vm.cid, disk.disk_cid)

          step.perform
        end

        it 'logs notification of detaching' do
          expect(logger).to receive(:info).with("Detaching disk #{disk.disk_cid}")

          step.perform
        end

        context 'when the CPI reports that a disk is not attached' do
          before do
            allow(cloud).to receive(:detach_disk)
              .with(vm.cid, disk.disk_cid)
              .and_raise(Bosh::Clouds::DiskNotAttached.new('foo'))
          end

          context 'and the disk is active' do
            before do
              disk.update(active: true)
            end

            it 'raises a CloudDiskNotAttached error' do
              expect { step.perform }.to raise_error(
                CloudDiskNotAttached,
                "'#{instance}' VM should have persistent disk '#{disk.disk_cid}' attached " \
                "but it doesn't (according to CPI)",
              )
            end
          end

          context 'and the disk is not active' do
            before do
              disk.update(active: false)
            end

            it 'does not raise any errors' do
              expect { step.perform }.not_to raise_error
            end
          end
        end

        context 'when given nil disk' do
          let(:disk) { nil }

          it 'does not perform any cloud actions' do
            expect(cloud).to_not receive(:detach_disk)

            step.perform
          end
        end
      end
    end
  end
end
