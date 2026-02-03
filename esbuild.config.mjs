import * as esbuild from "esbuild";
import postcss from "esbuild-postcss";

const watch = process.argv.includes("--watch");

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
});

if (watch) {
  await context.watch();
  console.log("Watching for changes...");
} else {
  await context.rebuild();
  await context.dispose();
}
