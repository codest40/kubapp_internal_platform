from pathlib import Path
import os
import subprocess
from datetime import datetime

manifest_list = {"requirements.txt": "python", "pyproject.toml": "python",
                 "pom.xml": "java", "build.gradle": "java",
                 "build.gradle.kts": "java", "package.json": "node",
                 "go.mod": "golang" }

extra_args_list = {
    "java": {"lint": ["mvn", "checkstyle:check"],
            "security": ["mvn", "org.owasp:dependency-check-maven:check", ],
            "test": ["mvn", "test"],
            "build": ["mvn", "package", "-DskipTests", ], },
}

b = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
print(b)
