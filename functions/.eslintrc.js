module.exports = {
  root: true,
  env: { es2020: true, node: true },
  extends: ["eslint:recommended", "plugin:@typescript-eslint/recommended", "google"],
  parser: "@typescript-eslint/parser",
  parserOptions: { project: ["tsconfig.json"], sourceType: "module" },
  plugins: ["@typescript-eslint"],
  ignorePatterns: ["/lib/**/*"],
  rules: {
    "require-jsdoc": "off",
    "max-len": "off",
    "@typescript-eslint/no-explicit-any": "off",

    "quotes": "off",
    "indent": "off",
    "comma-dangle": "off",
  },
};