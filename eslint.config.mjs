import { defineConfig, globalIgnores } from "eslint/config";
import eslint from "@eslint/js";
import next from "@next/eslint-plugin-next";
import jsxA11y from "eslint-plugin-jsx-a11y";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import tseslint from "typescript-eslint";

const eslintConfig = defineConfig([
  globalIgnores([
    ".next/**",
    ".vinext/**",
    ".sites-runtime/**",
    ".wrangler/**",
    "work/**",
    "dist/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  react.configs.flat.recommended,
  react.configs.flat["jsx-runtime"],
  reactHooks.configs.flat["recommended-latest"],
  jsxA11y.flatConfigs.recommended,
  next.configs["core-web-vitals"],
  // Legacy screens still use synchronous loading-state updates in effects.
  // Keep these findings visible while enforcing the rules on new code.
  {
    files: [
      "app/page.tsx",
      "features/access/AccessView.tsx",
      "features/attendance/AttendanceView.tsx",
      "features/dashboard/DashboardView.tsx",
      "features/families/FamiliesView.tsx",
      "features/groups/IndividualDiscipleshipView.tsx",
      "features/kids/KidsView.tsx",
      "features/people/PeopleView.tsx",
      "features/training/TrainingView.tsx",
    ],
    rules: { "react-hooks/set-state-in-effect": "warn" },
  },
  {
    files: ["features/groups/IndividualDiscipleshipView.tsx"],
    rules: {
      "react-hooks/purity": "warn",
      "@typescript-eslint/no-unused-vars": "warn",
    },
  },
  {
    files: ["features/kids/KidsView.tsx"],
    rules: {
      "@typescript-eslint/no-unused-vars": "warn",
      "@typescript-eslint/no-unused-expressions": "warn",
    },
  },
  {
    files: ["features/training/TrainingView.tsx"],
    rules: { "jsx-a11y/media-has-caption": "warn" },
  },
  {
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.serviceworker,
      },
    },
    settings: {
      react: {
        version: "detect",
      },
    },
  },
]);

export default eslintConfig;
