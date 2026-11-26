# Free Windows signing for Auralis

The release currently has no trusted Windows signing identity. Generating a
self-signed certificate does not remove public SmartScreen warnings.

[SignPath Foundation](https://signpath.org/) provides free code signing for
approved open-source projects. Its [terms](https://signpath.org/terms) and project
review apply; acceptance is not automatic. Apply using the public repository and
its license/build information. No application or account registration has been
submitted by the build scripts.

After approval, configure the assigned organization, project, signing policy,
artifact configuration and credentials in the release environment. Integration
must follow the approved service's build-origin requirements. Sign the executable
payload before packaging, then sign the resulting installer and verify its
Authenticode signature. Generate release hashes and updater metadata only after
the final signing step. Never modify a signed artifact afterwards. Keep private
signing keys and credentials out of this repository.

Signing identifies the publisher; it does not guarantee immediate SmartScreen
reputation or suppress malware detections. Microsoft's
[SmartScreen documentation](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)
explains the distinction. If an antivirus product reports a false positive,
submit the exact release artifact to that vendor for review. Do not disable
Defender, add exclusions, or instruct the installer to bypass Windows checks.
