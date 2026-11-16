import React from "react";
import { createRoot } from "react-dom/client";
import CrystalApp from "./CrystalApp";
import CrystalSettings from "./CrystalSettings";
import CrystalProgress from "./CrystalProgress";
import CrystalAdd from "./CrystalAdd";
import { CrystalProvider } from "./CrystalShared";
import "./crystal.css";

function Main() {
  const query = new URLSearchParams(window.location.search);
  const detail = Number(query.get("detail")) || 0;
  const properties = Number(query.get("properties")) || 0;
  const torrent = query.get("add") === "torrent";
  const url = query.get("add") === "url";
  if(query.has("settings")) return <CrystalSettings />;
  if(detail) return <CrystalProgress id={detail} />;
  if(properties) return <CrystalProgress id={properties} />;
  if(torrent || url) return <CrystalAdd mode={torrent ? "torrent" : "url"} />;
  return <CrystalApp />;
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode><CrystalProvider><Main /></CrystalProvider></React.StrictMode>
);
