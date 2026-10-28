from pathlib import Path
from platform_decision import KUBAPP_DECISION
from ai_analysis import analyze_data
import reuse


class CIRunner:
    def __init__(self, handler, use_script=False, ci_scripts=None):
        self.handler = handler
        self.use_script = use_script
        self.ci_scripts = ci_scripts

    def run_scripts(self):
        if not isinstance(self.ci_scripts, list) or not self.ci_scripts:
            raise RuntimeError(
                f"[{self.handler.app_name}] "
                "CI scripts must be a non-empty list of script paths."
            )

        app_root = Path(self.handler.app_dir).resolve()
        for script in self.ci_scripts:
            if not isinstance(script, str) or not script.strip():
                raise RuntimeError(
                    f"[{self.handler.app_name}] "
                    "Each CI script entry must be a nonempty path."
                )

            script_path = (app_root / script).resolve()
            try:
                relative_script = script_path.relative_to(app_root)
            except ValueError as exc:
                raise RuntimeError(
                    f"[{self.handler.app_name}] CI script must be inside "
                    f"the application directory: {script}"
                ) from exc

            if not script_path.is_file():
                raise RuntimeError(
                    f"[{self.handler.app_name}] CI script does not exist: "
                    f"{script_path}"
                )

            container_script = relative_script.as_posix()
            extension = script_path.suffix.lower()
            if extension == ".py":
                command = ["python", container_script]
            elif extension == ".sh":
                command = ["bash", container_script]
            else:
                raise RuntimeError(
                    f"[{self.handler.app_name}] Unsupported CI script "
                    f"extension '{extension}': {script}. "
                    "Only .py and .sh scripts are supported."
                )

            result = analyze_data({
                "app_name": self.handler.app_name,
                "artifact_type": "script",
                "script_content": reuse.collect_content(
                    script_path, allowed_root=app_root
                ),
                "component_dir": str(app_root),
                "runtime": self.handler.runtime,
            })

            KUBAPP_DECISION(result)
            reuse.run_component_command(
                command,
                component_environment=self.handler.component_environment,
                cwd=app_root,
                label=f"[{self.handler.app_name}] CI script: {script}",
            )

    def run(self):
        handler = self.handler
        execution_path = (
            "developer CI script"
            if self.use_script
            else "default CI checks"
        )
        print(
            f"[{handler.app_name}] Starting CI "
            f"using {execution_path}.",
            flush=True,
        )

        handler.install_dependencies()
        if self.use_script:
            self.run_scripts()
        else:
            handler.lint()
            handler.security_analysis()
            handler.unit_tests()

        if handler.extra_ci_commands:
            reuse.run_extra_checks(
                handler.extra_ci_commands,
                handler.runtime,
                handler.app_name,
                handler.app_dir,
                component_environment=handler.component_environment,
            )

        result = handler.build_from_dockerfile()
        print(
            f"[{handler.app_name}] CI completed successfully.",
            flush=True,
        )
        return result
