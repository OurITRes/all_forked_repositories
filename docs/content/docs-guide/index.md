---
layout: docs
title: "Documentation Site Guide to Managing Content"
---

## Purpose

This is a guide to managing RAC documentation, including step-by-step instructions for adding new content to GitHub and the [RAC Documentation Site](https://docs.rockarch.org/) and how to edit existing content that is already on the site. It also contains information about how to use GitHub and the Markdown format. For the policy that defines the approval process by which documentation is selected, designated as internal or external, and added to docs.rockarch.org, refer to the [RAC Documentation Site Content Approval Policy](https://docs.rockarch.org/docs-policy/).

## Platform Structural Overview

RAC staff can add documentation to the site via a repository on the [RAC’s GitHub](https://github.com/RockefellerArchiveCenter). A site generator called [Jekyll](https://jekyllrb.com/) converts the Markdown files that comprise the documentation into HTML. There are three URLs where the content is deployed:
1. [https://docs.rockarch.org/](https://docs.rockarch.org/): the public site which is available on the open web and does not include any internal documentation.
2. [https://docs-internal.rockarch.org/](https://docs-internal.rockarch.org/): the internal site which is only available on RAC networks, and contains internal-facing documentation. Traffic sent to this URL from outside the RAC network will be re-routed to the public site.
3. [https://docs-internal.dev.rockarch.org/](https://docs-internal.dev.rockarch.org/): the internal development site, used primarily as a preview for changes made to documentation.

GitHub is a web-based hosting service that enables version-control of content, meaning that it records and saves the changes to files over time and enables users to recall specific versions of those files. See [Using GitHub](using-github) for more information on Git and GitHub.
