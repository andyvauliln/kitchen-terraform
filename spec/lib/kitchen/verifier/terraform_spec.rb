# frozen_string_literal: true

# Copyright 2016 New Context Services, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "inspec"
require "kitchen"
require "kitchen/transport/ssh"
require "kitchen/verifier/terraform"
require "support/kitchen/terraform/config_attribute/color_examples"
require "support/kitchen/terraform/config_attribute/groups_examples"
require "support/kitchen/terraform/configurable_examples"

::RSpec
  .describe ::Kitchen::Verifier::Terraform do
    let :described_instance do
      described_class
        .new(
          color: false,
          groups:
            [
              {
                attributes: {attribute_name: "output_name"},
                controls: ["control"],
                hostnames: "hostnames",
                name: "name",
                port: 1234,
                ssh_key: "ssh_key",
                username: "username"
              }
            ],
          test_base_path: "/test/base/path"
        )
    end

    it_behaves_like "Kitchen::Terraform::ConfigAttribute::Color"

    it_behaves_like "Kitchen::Terraform::ConfigAttribute::Groups"

    it_behaves_like "Kitchen::Terraform::Configurable"

    describe "#call" do
      subject do
        lambda do
          described_instance.call kitchen_state
        end
      end

      let :kitchen_instance do
        ::Kitchen::Instance
          .new(
            driver: ::Kitchen::Driver::Base.new,
            logger: ::Kitchen::Logger.new,
            platform: ::Kitchen::Platform.new(name: "test-platform"),
            provisioner: ::Kitchen::Provisioner::Base.new,
            state_file:
              ::Kitchen::StateFile
                .new(
                  "/kitchen/root",
                  "test-suite-test-platform"
                ),
            suite: ::Kitchen::Suite.new(name: "test-suite"),
            transport: ssh_transport,
            verifier: described_instance
          )
      end

      let :ssh_transport do
        ::Kitchen::Transport::Ssh.new
      end

      before do
        described_instance.finalize_config! kitchen_instance
      end

      context "when the Kitchen state omits :kitchen_terraform_output" do
        let :kitchen_state do
          {}
        end

        it do
          is_expected
            .to(
              raise_error(
                ::Kitchen::ActionFailed,
                "The Kitchen state does not include :kitchen_terraform_output; this implies that the " \
                  "kitchen-terraform provisioner has not successfully converged"
              )
            )
        end
      end

      context "when the Kitchen state includes :kitchen_terraform_output" do
        let :kitchen_state do
          {kitchen_terraform_output: kitchen_terraform_output}
        end

        context "when the :kitchen_terraform_output does not include the configured :hostnames key" do
          let :kitchen_terraform_output do
            {}
          end

          it "raise an action failed error" do
            is_expected
              .to(
                raise_error(
                  ::Kitchen::ActionFailed,
                  /Enumeration of groups and hostnames resulted in failure/
                )
              )
          end
        end

        shared_context "Inspec::Profile" do
          let :profile do
            instance_double ::Inspec::Profile
          end

          before do
            allow(profile).to receive(:name).and_return "profile-name"
          end
        end

        shared_context "Inspec::Runner instance" do
          include_context "Inspec::Profile"

          let :runner do
            instance_double ::Inspec::Runner
          end

          before do
            allow(runner)
              .to(
                receive(:add_target)
                  .with(path: "/test/base/path/test-suite")
                  .and_return([profile])
              )
          end
        end

        shared_context "Inspec::Runner" do
          include_context "Inspec::Runner instance"

          let :runner_options do
            {
              "backend" => "ssh",
              "color" => false,
              "compression" => false,
              "compression_level" => 0,
              "connection_retries" => 5,
              "connection_retry_sleep" => 1,
              "connection_timeout" => 15,
              "host" => "hostname",
              "keepalive" => true,
              "keepalive_interval" => 60,
              "key_files" => ["ssh_key"],
              "logger" => kitchen_instance.logger,
              "max_wait_until_ready" => 600,
              "port" => 1234,
              "sudo" => false,
              "sudo_command" => "sudo -E",
              "sudo_options" => "",
              "user" => "username",
              attributes:
                {
                  "attribute_name" => "output_value",
                  "hostnames" => "hostname",
                  "output_name" => "output_value"
                },
              attrs: nil,
              backend_cache: false,
              controls: ["control"]
            }
          end

          before do
            allow(::Inspec::Runner)
              .to(
                receive(:new)
                  .with(runner_options)
                  .and_return(runner)
              )
          end
        end

        context "when the :kitchen_terraform_output does include the configured :hostnames key" do
          include_context "Inspec::Runner"

          let :kitchen_terraform_output do
            {
              "output_name" => {"value" => "output_value"},
              "hostnames" => {"value" => "hostname"}
            }
          end

          context "when the InSpec runner returns an exit code other than 0" do
            before do
              allow(runner)
                .to(
                  receive(:run)
                    .with(no_args)
                    .and_return(1)
                )
            end

            it "does raise an error" do
              is_expected
                .to(
                  raise_error(
                    ::Kitchen::ActionFailed,
                    "InSpec Runner exited with 1"
                  )
                )
            end
          end

          context "when the InSpec runner returns an exit code of 0" do
            before do
              allow(runner)
                .to(
                  receive(:run)
                    .with(no_args)
                    .and_return(0)
                )
            end

            it "does not raise an error" do
              is_expected.to_not raise_error
            end
          end
        end
      end
    end
  end
