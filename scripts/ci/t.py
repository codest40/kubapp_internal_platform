from dependency_abstractor import classify_apps
from validate import validate_apps

result = validate_apps()
classified = classify_apps(result["valid_apps"])

for app_dir, app_data in classified.items():
    print(f"\nParent: {app_dir}")

    for component in app_data:
        print(f"  App:       {component['app']}")
        print(f"  Component: {component['component_dir']}")
        print(f"  Manifest:  {component['manifest']}")
        print(f"  Dockerfile: {component['dockerfile']}")
