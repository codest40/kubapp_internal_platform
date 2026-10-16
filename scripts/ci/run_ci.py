from pathlib import Path
import sys
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
                script_path.relative_to(app_root)
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

            extension = script_path.suffix.lower()
            if extension == ".py":
                command = [sys.executable, str(script_path)]
            elif extension == ".sh":
                command = ["bash", str(script_path)]
            else:
                raise RuntimeError(
                    f"[{self.handler.app_name}] Unsupported CI script "
                    f"extension '{extension}': {script}. "
                    "Only .py and .sh scripts are supported."
                )

            reuse.run_command(
                command,
                cwd=app_root,
                label=f"[{self.handler.app_name}] CI script: {script}",
                env=self.handler.env,
            )

    def run(self):
        handler = self.handler
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
                env=handler.env,
            )

        return handler.build_from_dockerfile()
