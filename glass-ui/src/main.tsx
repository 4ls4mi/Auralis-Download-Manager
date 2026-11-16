import React from "react";
import { createRoot } from "react-dom/client";
import CrystalApp from "./CrystalApp";
import CrystalSettings from "./CrystalSettings";
import CrystalProgress from "./CrystalProgress";
import CrystalAdd from "./CrystalAdd";
import CrystalScheduler from "./CrystalScheduler";
import CrystalPower from "./CrystalPower";
import CrystalTool from "./CrystalTool";
import CrystalProperties from "./CrystalProperties";
import { CrystalFileInfo, CrystalComplete } from "./CrystalLifecycle";
import { CrystalProvider } from "./CrystalShared";
import "./crystal.css";
import "./crystal-overrides.css";
import "./ice-crystal.css";

function Main() {
  const query = new URLSearchParams(window.location.search);
  const detail = Number(query.get("detail")) || 0;
  const properties = Number(query.get("properties")) || 0;
  const torrent = query.get("add") === "torrent";
  const url = query.get("add") === "url";
  if(query.has("schedule")) return <CrystalScheduler/>;
  if(query.has("power")) return <CrystalPower id={Number(query.get("power"))}/>;
  if(query.has("tool")) return <CrystalTool kind={query.get("tool")??""} id={Number(query.get("id"))||0}/>;
  if(query.has("request")) return <CrystalFileInfo id={Number(query.get("request"))}/>;
  if(query.has("complete")) return <CrystalComplete id={Number(query.get("complete"))}/>;
  if(query.has("settings")) return <CrystalSettings />;
  if(detail) return <CrystalProgress id={detail} />;
  if(properties) return <CrystalProperties id={properties} />;
  if(torrent || url) return <CrystalAdd mode={torrent ? "torrent" : "url"} />;
  return <CrystalApp />;
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode><CrystalProvider><Main /></CrystalProvider></React.StrictMode>
);
