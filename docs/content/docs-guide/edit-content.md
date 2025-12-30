---
layout: docs
title: "Documentation Site Guide | Edit Content"
---

## Edit Content

To edit documentation that has already been added to GitHub and is on the website, work in the `development` branch of the GitHub repository for that set of documentation.

1. Commit changes with descriptive commit messages that describe the changes instead of the default "update [file]" message provided in GitHub. For example, messages like "add config values," "fix typo," or "adjust heading levels" clearly communicate what has changed.
2. Review the documentation on the [RAC development site](https://docs-internal.dev.rockarch.org/). A new commit to the `development` branch in GitHub will trigger the development site to update.
3. To get content on the production site, submit a pull request to merge `development` to the `base` branch of the GitHub repo.
4. Request review as necessary. As per the [Content Approval Policy](https://docs.rockarch.org/docs-policy/), the relevant Assistant Director and Program Director should review public documentation in the format they prefer. Once approved, merge the `development` branch into the `base` branch. The merge action will trigger the production site to add the new documentation to [docs.rockarch.org](https://docs.rockarch.org) for public access, or [docs-internal.rockarch.org](https://docs-internal.rockarch.org) for internal-only access.

Note: If a determination is made to either convert documentation from public to private, or to remove it completely, the Assistant Director for Digital Strategies or any other RAC employee with administrative access to the RAC GitHub account can be notified to enable this action.

## Add Images
Add image files to a subfolder in the GitHub repository titled `img`. Use Markdown syntax to include an image: `![image description](/repo-name/img/image-file-name.png)`.

## Add Internal Links
Add links between documents and sections using the format:

`This is a link to [another section](#header-name) in the same document`

`This is a link to [another file](/repo-name/file-name) in the same repository`

## Additional Styling

### HTML in Markdown

The [docs-build site code](https://github.com/RockefellerArchiveCenter/docs-build) contains stylesheets that specify the design of docs.rockarch.org. However, it is possible to add HTML and CSS markup directly into a Markdown file to adjust styles.

To style text as an example that will be set apart from the other text, assign the block of text a <div> tag and css class "docs-example." As specified in our custom CSS for the site, this will change the style to set the text apart:

```html
<div class="docs-example">
  <p> This is some example text </p>
</div>
```

Appears on the website as:

<div class="docs-example"><p>This is some example text</p></div>

### Inline Code and Code Blocks

Use backticks (`` ` ``) around the content to designate inline code in Markdown: `Example inline code`

For multi-line codeblocks, use three backticks before and after the codeblock. You can [specify the code language](https://github.com/rouge-ruby/rouge/wiki/List-of-supported-languages-and-lexers) after the first set of backticks to adjust the styles for that language. Example of an HTML code block:

````markdown
```html
<div class="col-sm-6 offset-sm-3">
  <h2 class="text-center">Filter by category</h2>
</div>
```
````



