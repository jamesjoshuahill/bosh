package brats_test

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/onsi/gomega/gexec"
)

var _ = Describe("Bosh Backup and Restore BBR", func() {
	BeforeEach(func() {
		startInnerBosh()
	})

	AfterEach(func() {
		err := os.RemoveAll(directorBackupName)
		Expect(err).ToNot(HaveOccurred())

		stopInnerBosh()
	})

	Context("database backup", func() {
		It("can backup and restore (removes underlying deployment and release)", func() {
			syslogManifestPath := assetPath("syslog-manifest.yml")
			osConfManifestPath := assetPath("os-conf-manifest.yml")

			By("create syslog deployment", func() {
				uploadStemcell("https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent")
				uploadRelease("https://bosh.io/d/github.com/cloudfoundry/syslog-release?v=11")

				session := bosh("-n", "deploy", syslogManifestPath, "-d", "syslog-deployment")
				Eventually(session, 3*time.Minute).Should(gexec.Exit(0))
			})

			By("create os-conf deployment", func() {
				uploadRelease("https://bosh.io/d/github.com/cloudfoundry/os-conf-release?v=12")

				session := bosh("-n", "deploy", osConfManifestPath, "-d", "os-conf-deployment")
				Eventually(session, 3*time.Minute).Should(gexec.Exit(0))
			})

			By("bbr creates a backup", func() {
				session := bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"backup")
				Eventually(session, 2*time.Minute).Should(gexec.Exit(0))
			})

			By("wipe system, recreate inner director", func() {
				stopInnerBosh()

				startInnerBosh()
			})

			By("expect deploy to fail because the release/stemcell won't be there", func() {
				session := bosh("-n", "deploy", syslogManifestPath, "-d", "syslog-deployment", "--recreate")
				Eventually(session, time.Minute).Should(gexec.Exit(1))
			})

			By("restore inner director from backup", func() {
				session := bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"restore")
				Eventually(session, 2*time.Minute).Should(gexec.Exit(0))

				waitForBoshDirectorUp(boshBinaryPath)

				stemcellUrl := "https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent"
				session = bosh("-n", "upload-stemcell", "--fix", stemcellUrl)
				Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
			})

			By("cck the deployments", func() {
				session := bosh("-n", "-d", "syslog-deployment", "cck", "--auto")
				Eventually(session, 10*time.Minute).Should(gexec.Exit(0))

				session = bosh("-n", "-d", "os-conf-deployment", "cck",
					"--resolution", "delete_vm_reference",
					"--resolution", "delete_disk_reference")
				Eventually(session, 10*time.Minute).Should(gexec.Exit(0))

				session = bosh("-n", "deploy", osConfManifestPath, "-d", "os-conf-deployment")
				Eventually(session, 3*time.Minute).Should(gexec.Exit(0))
			})

			By("validate deployments", func() {
				By("instance actually ran the jobs", func() {
					session := bosh("-n", "-d", "syslog-deployment", "instances",
						"--ps",
						"--column=process_state",
						"--column=instance")
					Eventually(session, time.Minute).Should(gexec.Exit(0))

					Expect(session.Out.Contents()).To(MatchRegexp("syslog_storer/[a-z0-9-]+[ \t]+running"))
					Expect(session.Out.Contents()).To(MatchRegexp("syslog_forwarder/[a-z0-9-]+[ \t]+running"))
				})

				By("persistent disks exist", func() {
					session := bosh("-n", "-d", "os-conf-deployment", "instances",
						"--details",
						"--column", "disk_cids",
					)

					Eventually(session, time.Minute).Should(gexec.Exit(0))

					Expect(string(session.Out.Contents())).To(MatchRegexp("[0-9a-f]{8}-[0-9a-f-]{27}"))
				})
			})
		})

		It("can backup and restore (reattaches to underlying deployment)", func() {
			By("Set up a deployment that uses the syslog release", func() {
				uploadStemcell("https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent")
				uploadRelease("https://bosh.io/d/github.com/cloudfoundry/syslog-release?v=11")

				manifestPath := assetPath("syslog-manifest.yml")
				session := bosh("-n", "deploy", manifestPath, "-d", "syslog-deployment")

				Eventually(session, 3*time.Minute).Should(gexec.Exit(0))
			})

			By("bbr creates a backup", func() {
				session := bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"backup")
				Eventually(session, time.Minute).Should(gexec.Exit(0))
			})

			By("wipe system", func() {
				session := outerBosh("-d", "bosh",
					"ssh", "bosh", "sudo rm -rf /var/vcap/store/blobstore/*")
				Eventually(session, 5*time.Minute).Should(gexec.Exit(0))

				session = bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"restore")
				Eventually(session, time.Minute).Should(gexec.Exit(0))

				waitForBoshDirectorUp(boshBinaryPath)

				stemcellUrl := "https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent"
				session = bosh("-n", "upload-stemcell", "--fix", stemcellUrl)
				Eventually(session, 5*time.Minute).Should(gexec.Exit(0))

				session = bosh("-n", "-d", "syslog-deployment", "cck", "--report")
				Eventually(session, 3*time.Minute).Should(gexec.Exit(0))
			})

			By("validate deployment. instance actually ran the jobs", func() {
				session := bosh("-n", "-d", "syslog-deployment", "instances",
					"--ps",
					"--column=process_state",
					"--column=instance",
				)
				Eventually(session, time.Minute).Should(gexec.Exit(0))

				Expect(session.Out.Contents()).To(MatchRegexp("syslog_storer/[a-z0-9-]+[ \t]+running"))
				Expect(session.Out.Contents()).To(MatchRegexp("syslog_forwarder/[a-z0-9-]+[ \t]+running"))
			})
		})
	})

	Context("blobstore files", func() {
		var directoriesBefore, filesBefore []string

		It("backs up an empty blobstore", func() {
			By("Backup deployment", func() {
				session := bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"backup")
				Eventually(session, time.Minute).Should(gexec.Exit(0))
			})

			By("Restore deployment", func() {
				session := bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"restore")
				Eventually(session, time.Minute).Should(gexec.Exit(0))

				waitForBoshDirectorUp(boshBinaryPath)
			})
		})

		It("restores the blobstore files with the correct permissions/ownership", func() {
			By("Upload a release", func() {
				uploadRelease("https://bosh.io/d/github.com/cloudfoundry/syslog-release?v=11")
			})

			By("Store directory/file structure before we do backup", func() {
				directoriesBefore, filesBefore = findBlobstoreFiles(outerBoshBinaryPath)
			})

			By("Backup deployment", func() {
				session := bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"backup")
				Eventually(session, time.Minute).Should(gexec.Exit(0))
			})

			By("Check directories are still there after backup", func() {
				directoriesAfter, filesAfter := findBlobstoreFiles(outerBoshBinaryPath)
				Expect(directoriesAfter).To(Equal(directoriesBefore))
				Expect(filesAfter).To(Equal(filesBefore))
			})

			By("\"wipe\" system", func() {
				session := outerBosh("-d", "bosh", "ssh", "bosh", "-c", "sudo rm -rf /var/vcap/store/blobstore/*")
				Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
			})

			By("Restore deployment", func() {
				session := bbr("director",
					"--host", fmt.Sprintf("%s:22", innerDirectorIP),
					"--username", innerDirectorUser,
					"--name", directorBackupName,
					"--private-key-path", innerBoshJumpboxPrivateKeyPath,
					"restore")
				Eventually(session, time.Minute).Should(gexec.Exit(0))

				waitForBoshDirectorUp(boshBinaryPath)
			})

			By("Check directories have correct permissions after restore", func() {
				directoriesAfter, filesAfter := findBlobstoreFiles(outerBoshBinaryPath)
				Expect(directoriesAfter).To(Equal(directoriesBefore))
				Expect(filesAfter).To(Equal(filesBefore))
			})
		})
	})
})

func waitForBoshDirectorUp(boshBinaryPath string) {
	Eventually(func() *gexec.Session {
		session := bosh("env")
		session.Wait()
		return session
	}, 5*time.Minute, 2*time.Second).Should(gexec.Exit(0))
}

func findBlobstoreFiles(outerBoshBinaryPath string) ([]string, []string) {
	session := outerBosh("-d", "bosh", "ssh", "bosh", "--results", "--column", "stdout",
		"sudo find /var/vcap/store/blobstore/store -type d -perm 0700 -user vcap -group vcap")
	Eventually(session, time.Minute).Should(gexec.Exit(0))

	directories := strings.Split(string(session.Out.Contents()), "\n")
	sort.Strings(directories)

	session = outerBosh("-d", "bosh", "ssh", "bosh", "-r", "--column", "stdout",
		"sudo find /var/vcap/store/blobstore/store -type f -perm 0600 -user vcap -group vcap")
	Eventually(session, time.Minute).Should(gexec.Exit(0))

	files := strings.Split(string(session.Out.Contents()), "\n")
	sort.Strings(files)

	return directories, files
}
