{ lib
, python3Packages
, fetchPypi
,
}:

python3Packages.buildPythonApplication rec {
  pname = "confluence-markdown-exporter";
  version = "4.0.4";
  pyproject = true;

  src = fetchPypi {
    pname = "confluence_markdown_exporter";
    inherit version;
    hash = "sha256-qyd9EeaXnDwACkvAGdIxXSfKELFPrD+zT0i2Z+qaX/g=";
  };

  build-system = with python3Packages; [
    hatchling
  ];

  dependencies = with python3Packages; [
    atlassian-python-api
    jmespath
    markdownify
    pydantic-settings
    pyyaml
    questionary
    rich
    tabulate
    typer
    python-dateutil
    lxml
  ];

  # CLI tool — no test suite in sdist
  doCheck = false;

  meta = with lib; {
    description = "Bulk-export Atlassian Confluence spaces and pages to local Markdown files";
    homepage = "https://github.com/Spenhouet/confluence-markdown-exporter";
    license = licenses.mit;
    mainProgram = "cme";
  };
}
