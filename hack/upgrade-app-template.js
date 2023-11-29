// Load the required modules
import * as fs from "fs"
import {parseDocument, YAMLMap, YAMLSeq} from "yaml"

// Get the file name from the command line argument
const fileName = process.argv[2]

// Check if the file name is valid
if (!fileName) {
  console.error("Please provide a YAML file name as an argument.")
  process.exit(1)
}

function assertInstanceOf(actual, type, message) {
  if (!actual instanceof type) {
    console.error(message);
    console.error(`actual: ${typeof actual}, expected: ${type}`);
    process.exit(1);
  }
}

function assertEquals(actual, expected, message) {
  if (actual !== expected) {
    console.error(message);
    console.error(`actual: ${actual}, expected: ${expected}`);
    process.exit(1);
  }
}

// Read the file contents
fs.readFile(fileName, "utf8", (err, data) => {
  // Handle any errors
  if (err) {
    console.error(err)
    process.exit(1)
  }

  // Parse the YAML data
  let obj = parseDocument(data);

  assertInstanceOf(obj, YAMLMap, "Yaml document must be a map");

  let kind = obj.get("kind");
  assertEquals(kind, "HelmRelease", "You must provide HelmRelease file");

  let chart = obj.getIn(["spec", "chart", "spec", "chart"]);
  assertEquals(chart, "app-template", "Unexpected chart name");

  let version = obj.getIn(["spec", "chart", "spec", "version"]);
  assertEquals(version, "1.5.1", "Unexpected chart version");

  obj.setIn(["spec", "chart", "spec", "version"], "2.3.0");

  let securityContext = obj.getIn(["spec", "values", "podSecurityContext"]);
  if (securityContext != null) {
    obj.setIn(["spec", "values", "defaultPodOptions", "securityContext"], securityContext);
    obj.deleteIn(["spec", "values", "podSecurityContext"]);
  }

  let image = obj.getIn(["spec", "values", "image"]);
  if (image != null) {
    obj.setIn(["spec", "values", "controllers", "main", "containers", "main", "image"], image);
    obj.deleteIn(["spec", "values", "image"]);
  }

  let probes = obj.getIn(["spec", "values", "probes"]);
  if (probes != null) {
    obj.setIn(["spec", "values", "controllers", "main", "containers", "main", "probes"], probes);
    obj.deleteIn(["spec", "values", "probes"]);
  }

  let services = obj.getIn(["spec", "values", "service"]);
  let mainServiceName = "main";
  let mainPortName = "http";
  if (services != null && services instanceof YAMLMap) {
    let mainService = services.items.at(0);
    mainServiceName = mainService.key;
    mainPortName = mainService.value.get("ports").items.at(0).key;
  }

  let ingress = obj.getIn(["spec", "values", "ingress"]);
  if (ingress != null && ingress instanceof YAMLMap) {
    ingress.items.forEach((item) => {
      let ingressClassName = item.value.get("ingressClassName");
      if (ingressClassName != null) {
        item.value.set("className", ingressClassName);
        item.value.delete("ingressClassName");
      }

      item.value.delete("enabled");

      let hosts = item.value.get("hosts");

      if (hosts != null && hosts instanceof YAMLSeq) {
        hosts.items.forEach((host) => {
          let paths = host.get("paths");
          if (paths != null && paths instanceof YAMLSeq) {
            paths.items.forEach((path) => {
              path.set("service", {
                name: "main",
                port: mainPortName
              });
            });
          }
        });
      }
    });
  }

  let persistences = obj.getIn(["spec", "values", "persistence"]);
  if (persistences != null && persistences instanceof YAMLMap) {
    persistences.items.forEach((persistence) => {
      let mountPath = persistence.value.get("mountPath");
      if (mountPath != null) {
        persistence.value.setIn(["globalMounts", 0, "path"], mountPath);
        persistence.value.delete("mountPath");
      }
    });
  }

  obj.getIn(["spec", "values"]).items.forEach(item => {
    item.value.comment = "\n"
  })

  obj.getIn(["spec", "values"]).commentBefore = "\n"

  // Convert the object back to YAML
  let output = obj.toString()

  // Write the output to the same file
  fs.writeFile(fileName, output, "utf8", (err) => {
    // Handle any errors
    if (err) {
      console.error(err)
      process.exit(1)
    }

    // Log a success message
    console.log("The file has been updated.")
  })
})
