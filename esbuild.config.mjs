import * as esbuild from "esbuild";
import postcss from "esbuild-postcss";

const watch = process.argv.includes("--watch");
const isProduction = process.env.NODE_ENV === "production" || process.env.RAILS_ENV === "production";

const context = await esbuild.context({
  entryPoints: [
    "app/javascript/application.ts",
    "app/javascript/application.css",
  ],
  bundle: true,
  sourcemap: true,
  format: "esm",
  outdir: "app/assets/builds",
  publicPath: "/assets",
  plugins: [postcss()],
  logLevel: "info",
  minify: isProduction,
  target: isProduction ? "es2020" : undefined,
});

if (watch) {
  await context.watch();
  console.log("Watching for changes...");
} else {
  await context.rebuild();
  await context.dispose();
}
