unit pTesteConfig;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.Classes, pConfig;

type
  [TestFixture]
  TTesteConfig = class
  private
    FPasta: string;
    FFb: string;
    function Gravar(const ALinhas: array of string): string;
    procedure CriarFirebirdFalso;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestCarregarGeralEBancos;
    [Test] procedure TestCarregarChaveAusenteUsaPadrao;
    [Test] procedure TestSalvarECarregarIdaEVolta;
    [Test] procedure TestValidarOk;
    [Test] procedure TestValidarHorarioInvalido;
    [Test] procedure TestValidarSemGbak;
    [Test] procedure TestValidarNomeInvalido;
    [Test] procedure TestValidarSemBanco;
    [Test] procedure TestValidarNenhumaCopia;
    [Test] procedure TestValidarRetencaoMenorQueUm;
    [Test] procedure TestValidarSemSenha;
  end;

implementation

procedure TTesteConfig.Setup;
begin
  FPasta := TPath.Combine(TPath.GetTempPath, 'fbbk_cfg_' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(FPasta);
  FFb := TPath.Combine(FPasta, 'fb');
end;

procedure TTesteConfig.TearDown;
begin
  TDirectory.Delete(FPasta, True);
end;

function TTesteConfig.Gravar(const ALinhas: array of string): string;
var
  L: TStringList;
  S: string;
begin
  Result := TPath.Combine(FPasta, 'backup.ini');
  L := TStringList.Create;
  try
    for S in ALinhas do
      L.Add(S);
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;

procedure TTesteConfig.TestValidarSemSenha;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := FPasta; C.Senha := '';
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'Senha');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.CriarFirebirdFalso;
begin
  TDirectory.CreateDirectory(FFb);
  TFile.WriteAllText(TPath.Combine(FFb, 'gbak.exe'), '');
  TFile.WriteAllText(TPath.Combine(FFb, 'nbackup.exe'), '');
  TFile.WriteAllText(TPath.Combine(FPasta, 'A.FDB'), '');
end;

procedure TTesteConfig.TestCarregarGeralEBancos;
var
  C: TConfig;
begin
  C := TConfig.Create;
  try
    C.Carregar(Gravar(['[Geral]', 'FirebirdDir=C:\FB', 'Usuario=SYSDBA', 'Senha=x',
      'Destino=D:\Bk', 'RetencaoDias=10', 'Horario=23:30', 'CopiaFbk=1', 'CopiaFdb=0',
      '[Banco1]', 'Nome=A', 'Arquivo=D:\A.FDB', '[Banco2]', 'Nome=B', 'Arquivo=D:\B.FDB',
      '[Banco4]', 'Nome=NAO_LIDO', 'Arquivo=D:\X.FDB']));
    Assert.AreEqual('C:\FB', C.FirebirdDir);
    Assert.AreEqual('SYSDBA', C.Usuario);
    Assert.AreEqual('x', C.Senha);
    Assert.AreEqual('D:\Bk', C.Destino);
    Assert.AreEqual(10, C.RetencaoDias);
    Assert.AreEqual('23:30', C.Horario);
    Assert.IsTrue(C.CopiaFbk);
    Assert.IsFalse(C.CopiaFdb);
    Assert.AreEqual(2, C.Bancos.Count);
    Assert.AreEqual('B', C.Bancos[1].Nome);
    Assert.AreEqual('D:\B.FDB', C.Bancos[1].Arquivo);
    Assert.AreEqual('C:\FB\gbak.exe', C.Gbak);
    Assert.AreEqual('C:\FB\nbackup.exe', C.Nbackup);
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestCarregarChaveAusenteUsaPadrao;
var
  C: TConfig;
begin
  C := TConfig.Create;
  try
    C.Carregar(Gravar(['[Geral]', 'RetencaoDias=abc']));
    Assert.AreEqual(7, C.RetencaoDias);
    Assert.AreEqual('02:00', C.Horario);
    Assert.AreEqual('SYSDBA', C.Usuario);
    Assert.IsTrue(C.CopiaFbk);
    Assert.IsTrue(C.CopiaFdb);
    Assert.AreEqual(0, C.Bancos.Count);
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestSalvarECarregarIdaEVolta;
var
  C, D: TConfig;
  B: TBancoConfig;
  Arq: string;
begin
  Arq := TPath.Combine(FPasta, 'novo.ini');
  C := TConfig.Create;
  D := TConfig.Create;
  try
    C.FirebirdDir := 'C:\FB'; C.Usuario := 'U'; C.Senha := 'S'; C.Destino := 'D:\Bk';
    C.RetencaoDias := 3; C.Horario := '01:15'; C.CopiaFbk := False; C.CopiaFdb := True;
    B.Nome := 'AG'; B.Arquivo := 'D:\AG.FDB'; C.Bancos.Add(B);
    B.Nome := 'XY'; B.Arquivo := 'D:\XY.FDB'; C.Bancos.Add(B);
    C.Salvar(Arq);
    // Salvar de novo com um banco a menos não pode deixar [Banco2] órfão
    C.Bancos.Delete(1);
    C.Salvar(Arq);
    D.Carregar(Arq);
    Assert.AreEqual('C:\FB', D.FirebirdDir);
    Assert.AreEqual('S', D.Senha);
    Assert.AreEqual(3, D.RetencaoDias);
    Assert.AreEqual('01:15', D.Horario);
    Assert.IsFalse(D.CopiaFbk);
    Assert.IsTrue(D.CopiaFdb);
    Assert.AreEqual(1, D.Bancos.Count);
    Assert.AreEqual('AG', D.Bancos[0].Nome);
  finally
    C.Free; D.Free;
  end;
end;

procedure TTesteConfig.TestValidarOk;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := TPath.Combine(FPasta, 'dest');
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsTrue(C.Validar(Erro), Erro);
    Assert.IsTrue(TDirectory.Exists(C.Destino), 'Validar deve criar o destino');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarHorarioInvalido;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := FPasta; C.Horario := '2:0';
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'Horario');
    Assert.IsFalse(TConfig.HorarioValido('24:00'));
    Assert.IsFalse(TConfig.HorarioValido('12:60'));
    Assert.IsTrue(TConfig.HorarioValido('00:00'));
    Assert.IsTrue(TConfig.HorarioValido('23:59'));
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarSemGbak;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  TFile.Delete(TPath.Combine(FFb, 'gbak.exe'));
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := FPasta;
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'gbak.exe');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarNomeInvalido;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := FPasta;
    B.Nome := 'A B'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'Nome');
    Assert.IsTrue(TConfig.NomeValido('AG2006_x-1'));
    Assert.IsFalse(TConfig.NomeValido(''));
    Assert.IsFalse(TConfig.NomeValido('a.b'));
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarSemBanco;
var
  C: TConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := FPasta;
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'banco');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarNenhumaCopia;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := FPasta; C.CopiaFbk := False; C.CopiaFdb := False;
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'cópia');
  finally
    C.Free;
  end;
end;

procedure TTesteConfig.TestValidarRetencaoMenorQueUm;
var
  C: TConfig;
  B: TBancoConfig;
  Erro: string;
begin
  CriarFirebirdFalso;
  C := TConfig.Create;
  try
    C.FirebirdDir := FFb; C.Senha := 'x'; C.Destino := FPasta; C.RetencaoDias := 0;
    B.Nome := 'A'; B.Arquivo := TPath.Combine(FPasta, 'A.FDB'); C.Bancos.Add(B);
    Assert.IsFalse(C.Validar(Erro));
    Assert.Contains(Erro, 'RetencaoDias');
  finally
    C.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteConfig);

end.
