unit pConfig;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, System.Generics.Collections;

type
  TBancoConfig = record
    Nome: string;
    Arquivo: string;
  end;

  TConfig = class
  public
    FirebirdDir: string;
    Usuario: string;
    Senha: string;
    Destino: string;
    RetencaoDias: Integer;
    Horario: string;
    CopiaFbk: Boolean;
    CopiaFdb: Boolean;
    Bancos: TList<TBancoConfig>;
    constructor Create;
    destructor Destroy; override;
    procedure Carregar(const AArquivo: string);
    procedure Salvar(const AArquivo: string);
    function Validar(out AErro: string): Boolean;
    function Gbak: string;
    function Nbackup: string;
    class function ArquivoPadrao: string;
    class function NomeValido(const ANome: string): Boolean;
    class function HorarioValido(const AHorario: string): Boolean;
  end;

implementation

uses
  System.IOUtils, System.Character, System.StrUtils;

const
  SGeral = 'Geral';

function SetErro(var AErro: string; const AMsg: string): Boolean;
begin
  AErro := AMsg;
  Result := False;
end;

constructor TConfig.Create;
begin
  inherited;
  Bancos := TList<TBancoConfig>.Create;
  Usuario := 'SYSDBA';
  RetencaoDias := 7;
  Horario := '02:00';
  CopiaFbk := True;
  CopiaFdb := True;
end;

destructor TConfig.Destroy;
begin
  Bancos.Free;
  inherited;
end;

class function TConfig.ArquivoPadrao: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'backup.ini');
end;

class function TConfig.NomeValido(const ANome: string): Boolean;
var
  C: Char;
begin
  Result := ANome <> '';
  for C in ANome do
    if (Ord(C) > 127) or not (C.IsLetterOrDigit or (C = '_') or (C = '-')) then
      Exit(False);
end;

class function TConfig.HorarioValido(const AHorario: string): Boolean;
var
  H, M: Integer;
begin
  Result := (Length(AHorario) = 5) and (AHorario[3] = ':')
    and TryStrToInt(Copy(AHorario, 1, 2), H) and TryStrToInt(Copy(AHorario, 4, 2), M)
    and (H >= 0) and (H <= 23) and (M >= 0) and (M <= 59);
end;

function TConfig.Gbak: string;
begin
  Result := TPath.Combine(FirebirdDir, 'gbak.exe');
end;

function TConfig.Nbackup: string;
begin
  Result := TPath.Combine(FirebirdDir, 'nbackup.exe');
end;

procedure TConfig.Carregar(const AArquivo: string);
var
  Ini: TIniFile;
  I: Integer;
  Secao: string;
  B: TBancoConfig;
begin
  Ini := TIniFile.Create(AArquivo);
  try
    FirebirdDir := Ini.ReadString(SGeral, 'FirebirdDir', '');
    Usuario := Ini.ReadString(SGeral, 'Usuario', 'SYSDBA');
    Senha := Ini.ReadString(SGeral, 'Senha', '');
    Destino := Ini.ReadString(SGeral, 'Destino', '');
    RetencaoDias := StrToIntDef(Ini.ReadString(SGeral, 'RetencaoDias', '7'), 7);
    Horario := Ini.ReadString(SGeral, 'Horario', '02:00');
    CopiaFbk := Ini.ReadString(SGeral, 'CopiaFbk', '1') = '1';
    CopiaFdb := Ini.ReadString(SGeral, 'CopiaFdb', '1') = '1';
    Bancos.Clear;
    I := 1;
    while True do
    begin
      Secao := 'Banco' + IntToStr(I);
      if not Ini.SectionExists(Secao) then
        Break;
      B.Nome := Ini.ReadString(Secao, 'Nome', '');
      B.Arquivo := Ini.ReadString(Secao, 'Arquivo', '');
      Bancos.Add(B);
      Inc(I);
    end;
  finally
    Ini.Free;
  end;
end;

procedure TConfig.Salvar(const AArquivo: string);
var
  Ini: TIniFile;
  I: Integer;
  Secao: string;
begin
  Ini := TIniFile.Create(AArquivo);
  try
    Ini.WriteString(SGeral, 'FirebirdDir', FirebirdDir);
    Ini.WriteString(SGeral, 'Usuario', Usuario);
    Ini.WriteString(SGeral, 'Senha', Senha);
    Ini.WriteString(SGeral, 'Destino', Destino);
    Ini.WriteString(SGeral, 'RetencaoDias', IntToStr(RetencaoDias));
    Ini.WriteString(SGeral, 'Horario', Horario);
    Ini.WriteString(SGeral, 'CopiaFbk', IfThen(CopiaFbk, '1', '0'));
    Ini.WriteString(SGeral, 'CopiaFdb', IfThen(CopiaFdb, '1', '0'));
    // Remove seções [BancoN] antigas para não deixar órfãs
    I := 1;
    while Ini.SectionExists('Banco' + IntToStr(I)) do
    begin
      Ini.EraseSection('Banco' + IntToStr(I));
      Inc(I);
    end;
    for I := 0 to Bancos.Count - 1 do
    begin
      Secao := 'Banco' + IntToStr(I + 1);
      Ini.WriteString(Secao, 'Nome', Bancos[I].Nome);
      Ini.WriteString(Secao, 'Arquivo', Bancos[I].Arquivo);
    end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

function TConfig.Validar(out AErro: string): Boolean;
var
  B: TBancoConfig;
begin
  Result := False;
  AErro := '';
  if not TFile.Exists(Gbak) then
    AErro := 'FirebirdDir: não encontrado gbak.exe em "' + FirebirdDir + '"'
  else if not TFile.Exists(Nbackup) then
    AErro := 'FirebirdDir: não encontrado nbackup.exe em "' + FirebirdDir + '"'
  else if Trim(Usuario) = '' then
    AErro := 'Usuario: informe o usuário do Firebird'
  else if Trim(Destino) = '' then
    AErro := 'Destino: informe a pasta de destino'
  else if RetencaoDias < 1 then
    AErro := 'RetencaoDias: deve ser 1 ou mais'
  else if not HorarioValido(Horario) then
    AErro := 'Horario: use o formato HH:MM (ex.: 02:00)'
  else if not (CopiaFbk or CopiaFdb) then
    AErro := 'Ative ao menos uma cópia (fbk ou fdb)'
  else if Bancos.Count = 0 then
    AErro := 'Informe ao menos um banco';
  if AErro <> '' then
    Exit;
  for B in Bancos do
  begin
    if not NomeValido(B.Nome) then
      Exit(SetErro(AErro, 'Nome do banco "' + B.Nome + '": use só letras, dígitos, "-" e "_"'));
    if not TFile.Exists(B.Arquivo) then
      Exit(SetErro(AErro, 'Banco "' + B.Nome + '": arquivo não encontrado "' + B.Arquivo + '"'));
  end;
  try
    if not TDirectory.Exists(Destino) then
      TDirectory.CreateDirectory(Destino);
  except
    on E: Exception do
      Exit(SetErro(AErro, 'Destino: não foi possível criar "' + Destino + '": ' + E.Message));
  end;
  Result := True;
end;

end.
