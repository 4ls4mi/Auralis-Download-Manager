import CrystalBrowserGuide from "./CrystalBrowserGuide";
import CrystalUpdateNotice from "./CrystalUpdateNotice";
import CrystalUpdateToast from "./CrystalUpdateToast";
import CrystalProgressTray from "./CrystalProgressTray";
import CrystalPrompt from "./CrystalPrompts";
import CrystalHelpers from "./CrystalHelpers";
import { CrystalWindow, WindowTop } from "./CrystalShared";
import CrystalDelete from "./CrystalDialog";
import CrystalConfirm from "./CrystalConfirm";
import React from "react";
import { createRoot } from "react-dom/client";
import { CrystalBatch, CrystalGrabber } from "./CrystalImports";
import CrystalApp from "./CrystalApp";
import CrystalSettings from "./CrystalSettings";
import CrystalProgress from "./CrystalProgress";
import CrystalAdd from "./CrystalAdd";
import CrystalScheduler from "./CrystalScheduler";
import CrystalPower from "./CrystalPower";
import CrystalTool from "./CrystalTool";
import CrystalVideo from "./CrystalVideo";
import CrystalGallery from "./CrystalGallery";
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
  if(query.get("tool")==="progress-tray") return <CrystalProgressTray/>;
  if(query.get("tool")==="browser-guide") return <CrystalBrowserGuide/>;
  if(query.get("tool")==="update-notice") return <CrystalUpdateNotice/>;
  if(query.get("tool")==="update-toast") return <CrystalUpdateToast/>;
  if(query.has("schedule")) return <CrystalScheduler/>;
  if(query.has("power")) return <CrystalPower id={Number(query.get("power"))}/>;
  if(query.get("tool")==="delete") return <CrystalDelete/>;
  if(query.get("tool")==="confirm") return <CrystalConfirm/>;
  if(query.get("tool")==="duplicate"||query.get("tool")==="queue") return <CrystalPrompt kind={query.get("tool") as "duplicate"|"queue"} lease={Number(query.get("lease"))}/>;
  if(query.get("tool")==="batch") return <CrystalBatch/>;
  if(query.get("tool")==="grabber") return <CrystalGrabber/>;
  if(query.get("tool")==="helpers") return <CrystalWindow target="details"><WindowTop title="Video and gallery tools"/><main className="cg-page cg-tool-body"><CrystalHelpers/></main></CrystalWindow>;
  if(query.get("tool")==="video") return <CrystalVideo/>;
  if(query.get("tool")==="gallery") return <CrystalGallery/>;
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
