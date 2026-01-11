# GitHub Configuration Templates

This directory contains GitHub configuration templates for new projects.

## Structure

```
github/
├── dependabot.yml           # Dependabot version update config
├── FUNDING.yml              # Sponsor button configuration
├── CODEOWNERS               # Code ownership rules
├── pull_request_template.md # PR template
├── workflows/
│   └── ci.yml               # Basic CI workflow
└── ISSUE_TEMPLATE/
    ├── bug_report.yml       # Bug report template
    └── feature_request.yml  # Feature request template
```

## Deployment

Templates are deployed to `~/.github-template/`.

## Usage

Copy templates to your project's `.github/` directory:

```bash
cp -r ~/.github-template/* /path/to/project/.github/
```

Or use a helper script to initialize a new project with these templates.

## Customization

- Edit `CODEOWNERS` to set your username
- Configure `FUNDING.yml` with your sponsorship links
- Modify workflow files based on your project's needs
