# Contributing

Every pull request must use the [pull request template](.github/pull_request_template.md) and include the following information. Complete every section before requesting review.

## Files allowed in contributor pull requests

Pull requests from forks targeting `master` may change Swift and Objective-C sources and headers, raster images and TGS animations, localization files, property lists, and shared Xcode project and workspace metadata. Asset catalogs may also change their `Contents.json` files. All added or modified files must be regular, non-executable files. The policy checks the PR diff and the proposed merge result, including both paths of a rename and the paths of deleted files.

Remove changes to scripts, PDF and SVG assets, compiled binaries, GitHub automation, or other files outside the allowlist before requesting review. The **Contributor PR files** status links to the workflow log, which lists the rejected paths. Review the contents of allowed files as part of the PR.

After the workflow has posted a status on GitHub, require **Contributor PR files** from GitHub Actions in the `master` branch ruleset and enable **Require branches to be up to date before merging**. The status applies to the exact test merge. Update the PR branch or rerun the workflow if GitHub generates a new test merge without a status. In **Settings → Actions → General**, require workflow approval for all external contributors so changes from forks cannot run a workflow before maintainer approval.

## Accessibility

Every new feature must include accessibility support and work with VoiceOver. Verify the feature with VoiceOver as part of testing, and describe the accessibility verification in the pull request.

## Key change

Describe the main change and the behavior it adds, fixes, or improves. Keep each pull request focused on one change.

## Reason

Explain why the change was made: the problem it solves or the need it addresses. Link a related issue if one exists.

## Screenshot/video result (before/after)

Attach screenshots or videos showing the behavior before and after the change. Label both clearly and use the same scenario so reviewers can compare the result.

If the change has no visible result, explain why screenshots or videos do not apply and include relevant verification output instead.

## Confirmation

Describe how you tested the change, including the steps performed, the expected result, and the actual result. Include the macOS version and app version/build used for testing behavior changes. For documentation-only changes, describe the content and links you checked.

Check the confirmation in the pull request template only after you have tested the affected behavior and verified that it works properly. Disclose any testing limitations.

Pull requests with missing information or an unchecked confirmation are not ready for review.
