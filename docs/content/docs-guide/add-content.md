---
layout: docs
title: "Documentation Site Guide | Add New Content"
---

## Add New Content to the Development Site

To get started, create a new RAC GitHub repository for the documentation using the [docs-template](https://github.com/RockefellerArchiveCenter/docs-template) repository template.
See the [Create a Repo Instructions](https://help.github.com/articles/create-a-repo/) from GitHub.

1. Choose a template: use `RockefellerArchiveCenter/docs-template`.
2. Designate the owner as the Rockefeller Archive Center.
3. Format the name using lowercase letters and dashes between words "short-name" (e.g. processing-manual).
4. Add a short description of the documentation.
5. Choose to make the repo public or private based on its pre-approved designation (see the [Rockefeller Archive Center Documentation Site Content Approval Policy](http://docs.rockarch.org/docs-policy/)).
6. Create a branch called `development` in the new repository.
7. The template will add all the [required files](#required-files) to the repository. Working in the `development` branch, edit the `README.md`, `index.md`, and `_config.yml` template files and add any new content. Use short, descriptive commit messages that describe the changes instead of the default "update [file]" message provided in GitHub. For example, messages like "add config values," "fix typo," or "adjust heading levels" clearly communicate what has changed.
8. To preview the documentation on the [development site](https://docs-internal.dev.rockarch.org/), ask a member of the Digital Strategies Team to do two things:
   - Give the new repository access to the necessary Organization Secrets in GitHub.
   - Add the documentation to the [docs-build repositories.yml](https://github.com/RockefellerArchiveCenter/docs-build/blob/base/repositories.yml). If the documentation is not approved for the public site, it will be added only under the `private` list in the `repositories.yml` file. If it is approved to be public, it will be added under both the `private` and `public` lists. Documentation should be added to the `repositories.yml` file as `RockefellerArchiveCenter/(name of the documentation)`.
9.  Preview the documentation on the [RAC development site](https://docs-internal.dev.rockarch.org/). A new commit to the `development` branch in GitHub will trigger the development site to update.

## Review and Add Content to the Production Site

1. To add content to the production site, submit a pull request to merge `development` to the `base` branch of the GitHub repo.
2. For technical review of configurations or Markdown, request a member of the Docs Team to review the pull request.
3.  As per the [Content Approval Policy](https://docs.rockarch.org/docs-policy/), the relevant Assistant Director and Program Director should review public documentation in the format they prefer.
4.  Once the pull request is approved, merge the `development` branch into the `base` branch. The merge action will trigger the production site to add the new documentation to [docs.rockarch.org](https://docs.rockarch.org) for public access, or [docs-internal.rockarch.org](https://docs-internal.rockarch.org) for internal-only access.

## Required Files
The template repository already includes these files, which can be edited as necessary for a particular set of documentation.

* `index.md`
* `README.md`
* `LICENSE.md`
* `_config.yml`
* `/.github/workflows/publish_sns.yml`

### index.md

`index.md` is a Markdown file that contains the first (or only) page of the documentation. Simple documentation like a short policy or one-page workflow should be added to this file. For multi-page documentation, see the [Multiple Documentation Files](#multiple-documentation-files) section below.

#### Page Title and Layout

At the beginning of `index.md` and all Markdown files that are part of the documentation, include a title and the type of layout. This is the title that will be displayed as the title of the webpage.

```
---
layout: docs
title:  "Guide to Processing Collections"
---
```

Note: the title of the page is the header 1. **The headings in the Markdown files should always start with heading level 2 (##)**. The level 2 headings will be used to build the table of contents on the website to improve user navigation.

#### Acknowledgements

Any institution or other’s work that we relied on in drafting our own documentation should be credited on the `index.md` page.

### Readme

Every GitHub repository requires a `README.md` file that includes information about what is in the repo and how to access and use the content. The README is formatted in Markdown and include a link to docs.rockarch.org. Edit the README from the template to include the name and a description of the documentation.

### License

All RAC documentation that is shared publicly on this platform will be made available under a [Creative Commons Zero](https://creativecommons.org/publicdomain/zero/1.0/) (CC0) public domain dedication, and all project-associated code is made available on the RAC organizational GitHub under an [MIT License](https://opensource.org/licenses/MIT).

The template repository already includes the CC0 License, so if it is public, no changes are necessary. If the content is private (for internal RAC staff use only), delete `LICENSE.md` and the reference to it in `README.md`.

###  \_config.yml

The template repository already includes this configuration file, which should be edited as specified for the site to build correctly. Note that quotation marks, spacing, and capitalization are important to follow precisely. Example `_config.yml`:

```
public: true
title: "Collection Policy"
description: "The main collecting areas of the Rockefeller Archive Center."
pages:
  - ["Rockefeller Archive Center Collection Policy", "index"]
```

`public` indicates whether or not the documentation should be public. Values should be either `public: true` or `public: false`.

`title` is the official title of the documentation, which will be displayed on the home page of the site.

`description` is a statement of what the documentation is. This text will become the description meta tag for the site, which is displayed in search-engine results, so keep it short and snappy.

`pages` is a list of lists of the pages included in this site. The first value in each list is the name, and the second is the filename of the page (without the extension). These values are used when building tables of contents.

### publish_sns.yml
In order to deliver update notifications to Amazon SNS (which will trigger a build of the site), a [GitHub Actions](https://github.com/RockefellerArchiveCenter/docs-build#github-action-configuration) file named `publish_sns.yml` needs to be in the `.github/workflows/` directory. The template repository already includes this file.

## Multiple Documentation Files

More complex documentation might be appropriately split into multiple files, which will translate into a corresponding number of web pages. In deciding how to divide the documentation, structure and present the content in a way that enhances navigation and use.

For example, in addition to an `index.md` file, the [Rockefeller Archive Center Guide to Processing Collections](http://docs.rockarch.org/processing_manual/) includes two other Markdown files that represent two different pages on docs.rockarch.org: Planning and Processing. All files should be in the root directory (no subfolders). Filenames should be short with no special characters or spaces. Use a hyphen between words instead of spaces. The filename will be part of the url of the site, so simple and concise are best.
