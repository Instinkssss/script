const fs=require('fs');
const KNOWN_SERVICES=["Players","RunService","ReplicatedStorage","VirtualUser","VirtualInputManager","UserInputService","StarterGui","HttpService"];
const KNOWN_PROPS=[
"Name","Size","Position","Parent","Text","Font","TextSize","TextColor3","TextXAlignment","BackgroundTransparency",
"BackgroundColor3","BorderSizePixel","TextTruncate","TextWrapped","Visible","ClipsDescendants","ZIndexBehavior",
"IgnoreGuiInset","ResetOnSpawn","CornerRadius","Color","Thickness","Transparency","ApplyStrokeMode","Padding",
"PaddingTop","PaddingLeft","PaddingRight","SortOrder","LayoutOrder","AutoButtonColor","Scale","Offset","X","Y",
"Material","CFrame","ClassName","PlaceId","GameId","JobId","Idled","Character","HumanoidRootPart","Backpack","PlayerGui",
"CurrentCamera","Position","Magnitude","LocalPlayer","GetDescendants","GetChildren","FindFirstChild","FindFirstChildOfClass",
"FireServer","InvokeServer","WaitForChild","Destroy","ClearAllChildren","GetAttributes","GetAttribute","GetFullName",
"Activate","CaptureController","ClickButton2","SendMouseButtonEvent","WorldToViewportPoint","fromRGB","new","Format","concatenate",
"AtEnd","Sibling","Border","Gotham","GothamBold","GothamMedium","Code","Grass","Ground","Mud","LeafyGrass","RemoteEvent",
"RemoteFunction","UnreliableRemoteEvent","BasePart","UICorner","UIStroke","UIPadding","UIListLayout","ScreenGui","Frame",
"TextLabel","TextButton","Enum","UDim2","UDim","Vector2","Vector3","CFrame","Color3","task","workspace","game","game:GetService",
"loadstring","getgenv","writefile","pcall","ipairs","pairs","tostring","tonumber","string","table","os","math","select",
"spawn","wait","tick","type","warn","print","continue","unpack","pcall","error","assert","next","rawget","setmetatable"
];
let bad=0;
for (const f of process.argv.slice(2)) {
  const src=fs.readFileSync(f,'utf8');
  // 1) dot-index akses AssignedGlobal yang mencurigakan: obj.Property (Property diawali huruf besar)
  const re=/\.\b([A-Z][A-Za-z0-9_]*)\b/g;
  let m, seen=new Set();
  while((m=re.exec(src))){
    const p=m[1];
    if(KNOWN_PROPS.includes(p)) continue;
    // skip: LuaObj.Field milik table kita sendiri
    if(["build","log","refresh","destroy","start","stop","toggle","reset","status","breakBlock","moveToBlock","findNearestBlock","resolveRemote","countInventory","waitForCollect","looksLikeBlock","getContainers","farmLoop","CONFIG","STATE","API","UI","C","REMOTES","BLOCK_CONTAINERS","BLOCK_KEYWORDS","MAX_DISTANCE","ACTION_DELAY","COLLECT_TIMEOUT","TELEPORT_TO_BLOCK","ANTI_AFK","AUTO_START","IDLE_STRIKES_MAX","Core","Main","Header","Status","Title","Close","Reopen","Action","Info","Stats","AccentBar"].includes(p)) continue;
    seen.add(p);
  }
  if(seen.size) { console.log("REVIEW "+f+" :: probable-unknown PascalCase props -> "+[...seen].join(", ")); bad++; }
  else console.log("CLEAN  "+f);
}
process.exit(0);
