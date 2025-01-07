# Packer Project

This project uses Packer to automate the creation of machine images.

## Variables

This project uses the following variables:

- `devportal_chart_version`: This variable is used to specify the version of the DevPortal chart.
- `admin_ui_chart_version`: This variable is used to specify the version of the Admin UI chart.

> [!NOTE]  
> If you don't specify the variables, the latest version of the charts will be used.

## Usage

To use this project, you need to set the variables `devportal_chart_version` and `admin_ui_chart_version` in your build command or `variable.pkr.hcl` file as default value.

```packer
packer build . -var devportal_chart_version = "1.0.0" -var admin_ui_chart_version = "1.0.0"
```