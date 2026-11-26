# SignPath application draft — owner review required

This draft has not been submitted. Signing is not configured or approved.

Project: Auralis Download Manager

Repository: https://github.com/4ls4mi/Auralis-Download-Manager

Maintainer account: https://github.com/4ls4mi

License: GPL-3.0. The project is a fork of Mister Download Manager and includes
third-party components and notices. SignPath must review eligibility rather than
assuming the fork qualifies automatically.

Requested service: free SignPath Foundation signing for the project's own Windows
executables and NSIS installer. Qt and other upstream binaries would be included
with their original signatures, if any, and licenses, rather than re-signed as
Auralis's own binaries.

Build: public GitHub Actions workflow, with a self-hosted Windows x64 build runner,
installer/upgrade/runtime checks, artifact digests, and a separate Linux publication
job. Please confirm whether this build-origin configuration satisfies the service's
requirements before configuring signing requests.

Important licensing disclosure: the normal Windows release includes interface
fonts distributed under permissions separately confirmed by the owner. Their
source editions include personal-use/demo or noncommercial terms; redistribution
permission does not establish an OSI-approved license. See
qt-ui/assets/fonts/SOURCES.md. Please confirm whether this artifact qualifies or
whether a separate edition containing only open-source/system fonts is required.
No font license or font choice has been changed for this application.

Network behavior to disclose: user-selected downloads and browser requests,
optional GitHub update checks, the Cloudflare-hosted release-notification feed,
optional helper downloads, optional file-host services, and BitTorrent traffic.
An Auralis-specific privacy policy must accurately document these connections and
their controls. The inherited website privacy policy describes the upstream MDM
project and must not be represented as an approved Auralis policy.

Owner confirmations needed before submission:

- Contact details, repository ownership, and MFA status.
- Named committers/reviewers and signing approvers.
- Eligibility of the current font bundle, or the desired open-source-only edition.
- An accurate project privacy policy and accepted build-origin configuration.
- Provider approval before claiming signing sponsorship or enabling a signing job.

Other paths: Microsoft Store distribution of a reviewed MSIX package, or a paid
publicly trusted signing service/certificate for direct installer distribution.
Neither self-signing nor renaming/repacking the executable establishes public
publisher trust. A genuine antivirus false positive requires vendor review of the
exact artifact; signing alone is not a malware-detection exemption.

References:
https://signpath.org/terms
https://signpath.org/apply
https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation
