import js from '@eslint/js';
import globals from 'globals';

export default [
  { ignores: ['node_modules/**', 'dist/**', '.stage-*/**'] },
  js.configs.recommended,
  { files: ['**/*.mjs','eslint.config.js'], languageOptions: { globals: globals.node } },
  { files: ['public/**/*.js'], languageOptions: { globals: globals.browser } },
  { rules: { 'no-unused-vars': ['error', {args:'after-used', caughtErrors:'none'}],
    'no-control-regex':'off' } }
];
