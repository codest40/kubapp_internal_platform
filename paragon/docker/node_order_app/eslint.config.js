const eslintConfig = [
    {
        files: ["**/*.js"],
        languageOptions: {
            ecmaVersion: 2022,
            sourceType: "commonjs",
            globals: {
                process: "readonly",
                console: "readonly"
            }
        },
        rules: {
            "no-unused-vars": "error",
            "no-undef": "error",
            "semi": ["error", "always"],
            "quotes": ["error", "double"],
            "indent": ["error", 4]
        }
    }
];

module.exports = eslintConfig;
