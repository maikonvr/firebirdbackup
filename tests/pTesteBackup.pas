unit pTesteBackup;

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils, System.IniFiles,
  System.Generics.Collections, System.StrUtils, Winapi.Windows, pConfig, pLog, pProcesso, pBackup;

type
  [TestFixture]
  TTesteBackup = class
  private
    FPasta, FDestino, FFb: string;
    FConfig: TConfig;
    FLog: TLog;
    FChamadas: TStringList;      // "exe|args"
    FAmbientes: TStringList;     // "ISC_USER;ISC_PASSWORD" por chamada
    FCodigos: TDictionary<string, Integer>; // prefixo de "exe|args" -> exit code (padrão 0)
    FLevantar: string;           // prefixo de "exe|args" que faz o executor falso levantar EProcesso
    FMarcadorNoLock: Boolean;    // o marcador .lock-pendente existia quando o -L rodou?
    procedure CriarArquivo(const ANome: string; ADataModif: TDateTime; ATamanho: Integer = 0);
    procedure AddBanco(const ANome: string);
    function ExecutorFalso: TExecutor;
    function Chamada(I: Integer): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestNomeArquivoBackup;
    [Test] procedure TestCasaPadraoRetencao;
    [Test] procedure TestRetencaoApagaSoAntigosNoPadrao;
    [Test] procedure TestGravarELerStatus;
    [Test] procedure TestSequenciaCompletaOk;
    [Test] procedure TestComandoGbakComEspacos;
    [Test] procedure TestSoFbkQuandoFdbDesligado;
    [Test] procedure TestGbakFalhaRegistraEContinuaFdb;
    [Test] procedure TestLockFalhaNaoCopiaNemDestrava;
    [Test] procedure TestCopiaFalhaAindaDestrava;
    [Test] procedure TestLockPendenteDestravaAntes;
    [Test] procedure TestLockPendenteOrfaoNaoAborta;
    [Test] procedure TestEspacoInsuficientePulaBanco;
    [Test] procedure TestExecutarTodosGravaStatusERetencao;
    [Test] procedure TestSenhaNaoVaiParaOLog;
    [Test] procedure TestExcecaoNoExecutorViraFalhaENaoImpedeSeguinte;
    [Test] procedure TestLockPendenteRecuperacaoFalhaMantemMarcador;
    [Test] procedure TestExecutarConcorrenteSaiComAviso;
    [Test] procedure TestStatusUsaHoraDeInicio;
    [Test] procedure TestExecutarComDestinoInvalidoNaoLevanta;
    [Test] procedure TestMarcadorExisteDuranteLock;
    [Test] procedure TestRetencaoUsaDataDoNomeNaoDoArquivo;
    [Test] procedure TestCopiaInformaProgresso;
  end;

implementation

procedure TTesteBackup.Setup;
begin
  FPasta := TPath.Combine(TPath.GetTempPath, 'fbbk_bk_' + TPath.GetGUIDFileName);
  FDestino := TPath.Combine(FPasta, 'dest');
  FFb := TPath.Combine(FPasta, 'fb');
  TDirectory.CreateDirectory(FDestino);
  TDirectory.CreateDirectory(FFb);
  TFile.WriteAllText(TPath.Combine(FFb, 'gbak.exe'), '');
  TFile.WriteAllText(TPath.Combine(FFb, 'nbackup.exe'), '');
  FConfig := TConfig.Create;
  FConfig.FirebirdDir := FFb;
  FConfig.Destino := FDestino;
  FConfig.Senha := 'segredo';
  FLog := TLog.Create(FDestino);
  FChamadas := TStringList.Create;
  FAmbientes := TStringList.Create;
  FCodigos := TDictionary<string, Integer>.Create;
end;

procedure TTesteBackup.TearDown;
begin
  FCodigos.Free;
  FAmbientes.Free;
  FChamadas.Free;
  FLog.Free;
  FConfig.Free;
  TDirectory.Delete(FPasta, True);
end;

function TTesteBackup.ExecutorFalso: TExecutor;
begin
  Result := function(const AExe, AArgs: string; AAmbiente: TStrings; AOnLinha: TLinhaEvento;
    ATimeoutMs: Cardinal): Integer
    var
      Chave: string;
      Destino: string;
    begin
      FChamadas.Add(ExtractFileName(AExe) + '|' + AArgs);
      if (FLevantar <> '') and StartsText(FLevantar, ExtractFileName(AExe) + '|' + AArgs) then
        raise EProcesso.Create('falha simulada ao executar ' + ExtractFileName(AExe));
      if SameText(ExtractFileName(AExe), 'nbackup.exe') and StartsText('-L ', AArgs) then
        FMarcadorNoLock := TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente'));
      if Assigned(AAmbiente) then
        FAmbientes.Add(AAmbiente.Values['ISC_USER'] + ';' + AAmbiente.Values['ISC_PASSWORD'])
      else
        FAmbientes.Add('');
      if Assigned(AOnLinha) then
        AOnLinha('saida ' + Copy(AArgs, 1, 2));
      // gbak -b: simula criando o arquivo de saída (último argumento entre aspas)
      if SameText(ExtractFileName(AExe), 'gbak.exe') then
      begin
        Destino := AArgs;
        Delete(Destino, 1, LastDelimiter('"', Copy(Destino, 1, Length(Destino) - 1)));
        Destino := Copy(Destino, 1, Length(Destino) - 1);
        TFile.WriteAllText(Destino, 'fbk-falso');
      end;
      Result := 0;
      for Chave in FCodigos.Keys do
        if StartsText(Chave, ExtractFileName(AExe) + '|' + AArgs) then
          Result := FCodigos[Chave];
    end;
end;

function TTesteBackup.Chamada(I: Integer): string;
begin
  if I < FChamadas.Count then
    Result := FChamadas[I]
  else
    Result := '<nenhuma>';
end;

procedure TTesteBackup.CriarArquivo(const ANome: string; ADataModif: TDateTime; ATamanho: Integer);
var
  Arq: string;
begin
  Arq := TPath.Combine(FDestino, ANome);
  TFile.WriteAllText(Arq, StringOfChar('x', ATamanho));
  TFile.SetLastWriteTime(Arq, ADataModif);
end;

procedure TTesteBackup.AddBanco(const ANome: string);
var
  B: TBancoConfig;
begin
  B.Nome := ANome;
  B.Arquivo := TPath.Combine(FPasta, ANome + '.FDB');
  TFile.WriteAllText(B.Arquivo, 'db');
  FConfig.Bancos.Add(B);
end;

procedure TTesteBackup.TestNomeArquivoBackup;
begin
  Assert.AreEqual('D:\Bk\AG2006_2026-10-05_0200.fbk',
    TBackup.NomeArquivoBackup('D:\Bk', 'AG2006', EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 7, 0), '.fbk'));
end;

procedure TTesteBackup.TestCasaPadraoRetencao;
var
  Nomes: TArray<string>;
begin
  Nomes := ['AG2006', 'Outro'];
  Assert.IsTrue(TBackup.CasaPadraoRetencao('AG2006_2026-10-05_0200.fbk', Nomes));
  Assert.IsTrue(TBackup.CasaPadraoRetencao('ag2006_2026-10-05_0200.FDB', Nomes));
  Assert.IsTrue(TBackup.CasaPadraoRetencao('backup_2026-10-05.log', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006.FDB', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006_2026-10-05_0200.rar', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('XYZ_2026-10-05_0200.fbk', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006_2026-10-05.fbk', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('ultimo-status.ini', Nomes));
end;

procedure TTesteBackup.TestRetencaoApagaSoAntigosNoPadrao;
var
  Bk: TBackup;
  Hoje: TDateTime;
begin
  AddBanco('AG');
  FConfig.RetencaoDias := 7;
  Hoje := EncodeDate(2026, 10, 20);
  CriarArquivo('AG_2026-10-01_0200.fbk', Hoje - 19);    // apaga
  CriarArquivo('AG_2026-10-12_0200.fdb', Hoje - 8);     // apaga
  CriarArquivo('AG_2026-10-14_0200.fbk', Hoje - 6);     // mantém
  CriarArquivo('backup_2026-10-01.log', Hoje - 19);      // apaga
  CriarArquivo('OUTRO_2026-10-01_0200.fbk', Hoje - 19);  // mantém: banco não configurado
  CriarArquivo('importante.txt', Hoje - 30);             // mantém
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := Hoje;
    Bk.AplicarRetencao;
  finally
    Bk.Free;
  end;
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-01_0200.fbk')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-12_0200.fdb')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'backup_2026-10-01.log')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-14_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'OUTRO_2026-10-01_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'importante.txt')));
end;

procedure TTesteBackup.TestGravarELerStatus;
var
  Bk: TBackup;
  R: TArray<TResultadoBanco>;
  Ini: TIniFile;
begin
  AddBanco('AG');
  SetLength(R, 2);
  R[0].Nome := 'AG'; R[0].Inicio := EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0);
  R[0].Fim := R[0].Inicio + EncodeTime(0, 1, 30, 0); R[0].OK := True; R[0].Mensagem := '';
  R[0].TamanhoFbk := 1234; R[0].TamanhoFdb := 5678;
  R[1].Nome := 'XY'; R[1].Inicio := R[0].Fim; R[1].Fim := R[0].Fim; R[1].OK := False;
  R[1].Mensagem := 'falhou';
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := R[0].Inicio;
    Bk.GravarStatus(R, R[0].Inicio);
  finally
    Bk.Free;
  end;
  Ini := TIniFile.Create(TPath.Combine(FDestino, 'ultimo-status.ini'));
  try
    Assert.AreEqual('ERRO', Ini.ReadString('Geral', 'Resultado', ''));
    Assert.AreEqual('2026-10-05 02:00:00', Ini.ReadString('Geral', 'UltimaExecucao', ''));
    Assert.AreEqual('OK', Ini.ReadString('AG', 'Resultado', ''));
    Assert.AreEqual(90, Ini.ReadInteger('AG', 'DuracaoSeg', -1));
    Assert.AreEqual('1234', Ini.ReadString('AG', 'TamanhoFbk', ''));
    Assert.AreEqual('falhou', Ini.ReadString('XY', 'Mensagem', ''));
  finally
    Ini.Free;
  end;
  Assert.AreEqual(R[0].Inicio, TBackup.LerUltimaExecucao(FDestino), 0.00001);
  Assert.AreEqual(0.0, TBackup.LerUltimaExecucao(TPath.Combine(FPasta, 'vazio')), 0.00001);
end;

procedure TTesteBackup.TestSequenciaCompletaOk;
var
  Bk: TBackup;
  R: TResultadoBanco;
  Arq, Fbk, Fdb: string;
begin
  AddBanco('AG');
  Arq := FConfig.Bancos[0].Arquivo;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.Agora := EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0);
    Bk.EspacoLivreFixo := High(Int64);
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Fbk := TPath.Combine(FDestino, 'AG_2026-10-05_0200.fbk');
  Fdb := TPath.Combine(FDestino, 'AG_2026-10-05_0200.fdb');
  Assert.IsTrue(R.OK, R.Mensagem);
  Assert.AreEqual(4, FChamadas.Count);
  Assert.AreEqual('gbak.exe|-b -g -v -se localhost:service_mgr "' + Arq + '" "' + Fbk + '"', Chamada(0));
  Assert.AreEqual('nbackup.exe|-L "' + Arq + '"', Chamada(1));
  Assert.AreEqual('nbackup.exe|-N "' + Arq + '"', Chamada(2));
  Assert.AreEqual('nbackup.exe|-F "' + Fdb + '"', Chamada(3));
  Assert.AreEqual('SYSDBA;segredo', FAmbientes[0]);
  Assert.AreEqual('SYSDBA;segredo', FAmbientes[1]);
  Assert.IsTrue(TFile.Exists(Fbk));
  Assert.IsTrue(TFile.Exists(Fdb), 'cópia física deve existir');
  Assert.AreEqual('db', TFile.ReadAllText(Fdb));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
  Assert.AreEqual(Int64(9), R.TamanhoFbk);
  Assert.AreEqual(Int64(2), R.TamanhoFdb);
end;

procedure TTesteBackup.TestComandoGbakComEspacos;
var
  Bk: TBackup;
  B: TBancoConfig;
  Dir: string;
begin
  Dir := TPath.Combine(FPasta, 'com espaco');
  TDirectory.CreateDirectory(Dir);
  B.Nome := 'AG'; B.Arquivo := TPath.Combine(Dir, 'AG.FDB');
  TFile.WriteAllText(B.Arquivo, 'db');
  FConfig.Bancos.Add(B);
  FConfig.CopiaFdb := False;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    Bk.ExecutarBanco(B);
  finally
    Bk.Free;
  end;
  Assert.Contains(Chamada(0), '"' + B.Arquivo + '"');
end;

procedure TTesteBackup.TestSoFbkQuandoFdbDesligado;
var
  Bk: TBackup;
begin
  AddBanco('AG');
  FConfig.CopiaFdb := False;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsTrue(Bk.ExecutarBanco(FConfig.Bancos[0]).OK);
  finally
    Bk.Free;
  end;
  Assert.AreEqual(1, FChamadas.Count);
  Assert.StartsWith('gbak.exe|', Chamada(0));
end;

procedure TTesteBackup.TestGbakFalhaRegistraEContinuaFdb;
var
  Bk: TBackup;
  R: TResultadoBanco;
begin
  AddBanco('AG');
  FCodigos.Add('gbak.exe|', 1);
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.IsFalse(R.OK);
  Assert.Contains(R.Mensagem, 'gbak');
  Assert.AreEqual(4, FChamadas.Count, 'cópia fdb ainda roda');
end;

procedure TTesteBackup.TestLockFalhaNaoCopiaNemDestrava;
var
  Bk: TBackup;
  R: TResultadoBanco;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  FCodigos.Add('nbackup.exe|-L', 1);
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.IsFalse(R.OK);
  Assert.AreEqual(1, FChamadas.Count);
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
end;

procedure TTesteBackup.TestCopiaFalhaAindaDestrava;
var
  Bk: TBackup;
  R: TResultadoBanco;
  Fdb: string;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  // Forçar falha da cópia: o destino já existe como somente leitura (CopyFile dá acesso negado)
  Fdb := TPath.Combine(FDestino, 'AG_2026-10-05_0200.fdb');
  TFile.WriteAllText(Fdb, 'velho');
  TFile.SetAttributes(Fdb, [TFileAttribute.faReadOnly]);
  try
    Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
    try
      Bk.Agora := EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0);
      Bk.EspacoLivreFixo := High(Int64);
      R := Bk.ExecutarBanco(FConfig.Bancos[0]);
    finally
      Bk.Free;
    end;
  finally
    TFile.SetAttributes(Fdb, [TFileAttribute.faNormal]);
  end;
  Assert.IsFalse(R.OK);
  Assert.Contains(R.Mensagem, 'cópia');
  Assert.AreEqual('nbackup.exe|-L "' + FConfig.Bancos[0].Arquivo + '"', Chamada(0));
  Assert.AreEqual('nbackup.exe|-N "' + FConfig.Bancos[0].Arquivo + '"', Chamada(1));
  Assert.AreEqual(2, FChamadas.Count, 'sem -F quando a cópia falhou');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
end;

procedure TTesteBackup.TestLockPendenteDestravaAntes;
var
  Bk: TBackup;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  TFile.WriteAllText(TPath.Combine(FDestino, 'AG.lock-pendente'), '');
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsTrue(Bk.ExecutarBanco(FConfig.Bancos[0]).OK);
  finally
    Bk.Free;
  end;
  Assert.AreEqual('nbackup.exe|-N "' + FConfig.Bancos[0].Arquivo + '"', Chamada(0));
  Assert.AreEqual('nbackup.exe|-L "' + FConfig.Bancos[0].Arquivo + '"', Chamada(1));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
end;

procedure TTesteBackup.TestLockPendenteOrfaoNaoAborta;
var
  Bk: TBackup;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  TFile.WriteAllText(TPath.Combine(FDestino, 'AG.lock-pendente'), '');
  FCodigos.Add('nbackup.exe|-N', 1);   // banco não estava travado: -N falha
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    // o -N da recuperação falha (aviso); o -N normal depois do -L também "falha" aqui,
    // então o resultado é ERRO, mas a sequência completa precisa ter rodado
    Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.AreEqual(3, FChamadas.Count);
  Assert.StartsWith('nbackup.exe|-N', Chamada(0));
  Assert.StartsWith('nbackup.exe|-L', Chamada(1));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')),
    'o -N normal falhou: marcador fica para nova tentativa na próxima execução');
end;

procedure TTesteBackup.TestEspacoInsuficientePulaBanco;
var
  Bk: TBackup;
  R: TResultadoBanco;
begin
  AddBanco('AG');   // arquivo tem 2 bytes; exige 4 com as duas cópias
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := 3;
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.IsFalse(R.OK);
  Assert.Contains(R.Mensagem, 'spaço');
  Assert.AreEqual(0, FChamadas.Count);
end;

procedure TTesteBackup.TestExecutarTodosGravaStatusERetencao;
var
  Bk: TBackup;
  Hoje: TDateTime;
begin
  AddBanco('AG');
  AddBanco('XY');
  FConfig.CopiaFdb := False;
  FConfig.RetencaoDias := 7;
  // data real: o arquivo criado pelo executor falso recebe LastWriteTime de agora,
  // e uma data fictícia no futuro faria a retenção apagá-lo
  Hoje := Trunc(Date) + EncodeTime(2, 0, 0, 0);
  CriarArquivo(ExtractFileName(TBackup.NomeArquivoBackup(FDestino, 'AG', Hoje - 19, '.fbk')), Hoje - 19);
  FCodigos.Add('gbak.exe|-b -g -v -se localhost:service_mgr "' + FConfig.Bancos[1].Arquivo, 1);
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.Agora := Hoje;
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsFalse(Bk.Executar, 'XY falhou, resultado geral ERRO');
  finally
    Bk.Free;
  end;
  Assert.AreEqual(2, FChamadas.Count);
  Assert.IsFalse(TFile.Exists(TBackup.NomeArquivoBackup(FDestino, 'AG', Hoje - 19, '.fbk')), 'fbk velho apagado');
  Assert.IsTrue(TFile.Exists(TBackup.NomeArquivoBackup(FDestino, 'AG', Hoje, '.fbk')), 'fbk de hoje mantido');
  Assert.AreEqual(Hoje, TBackup.LerUltimaExecucao(FDestino), 0.00001);
end;

procedure TTesteBackup.TestSenhaNaoVaiParaOLog;
var
  Bk: TBackup;
  Texto: string;
begin
  AddBanco('AG');
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.Agora := EncodeDate(2026, 10, 5);
    FLog.Agora := Bk.Agora;   // o log usa a data real; o teste lê o arquivo de 2026-10-05
    Bk.EspacoLivreFixo := High(Int64);
    Bk.Executar;
  finally
    Bk.Free;
  end;
  Texto := TFile.ReadAllText(TLog.NomeArquivo(FDestino, EncodeDate(2026, 10, 5)));
  Assert.DoesNotContain(Texto, 'segredo');
  Assert.Contains(Texto, 'gbak');
end;

procedure TTesteBackup.TestExcecaoNoExecutorViraFalhaENaoImpedeSeguinte;
var
  Bk: TBackup;
  Ini: TIniFile;
  Hoje: TDateTime;
begin
  AddBanco('AG');
  AddBanco('XY');
  FConfig.CopiaFdb := False;
  Hoje := Trunc(Date) + EncodeTime(2, 0, 0, 0);
  FLevantar := 'gbak.exe|-b -g -v -se localhost:service_mgr "' + FConfig.Bancos[0].Arquivo;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.Agora := Hoje;
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsFalse(Bk.Executar, 'AG falhou por exceção');
  finally
    Bk.Free;
  end;
  Assert.AreEqual(2, FChamadas.Count, 'XY ainda roda');
  Assert.IsTrue(TFile.Exists(TBackup.NomeArquivoBackup(FDestino, 'XY', Hoje, '.fbk')));
  Ini := TIniFile.Create(TPath.Combine(FDestino, 'ultimo-status.ini'));
  try
    Assert.AreEqual('ERRO', Ini.ReadString('AG', 'Resultado', ''));
    Assert.Contains(Ini.ReadString('AG', 'Mensagem', ''), 'falha simulada');
    Assert.AreEqual('OK', Ini.ReadString('XY', 'Resultado', ''));
  finally
    Ini.Free;
  end;
end;

procedure TTesteBackup.TestLockPendenteRecuperacaoFalhaMantemMarcador;
var
  Bk: TBackup;
  R: TResultadoBanco;
begin
  AddBanco('AG');
  FConfig.CopiaFdb := False;   // só fbk: nenhum -N normal depois
  TFile.WriteAllText(TPath.Combine(FDestino, 'AG.lock-pendente'), '');
  FCodigos.Add('nbackup.exe|-N', 1);   // serviço fora do ar, por exemplo
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    R := Bk.ExecutarBanco(FConfig.Bancos[0]);
  finally
    Bk.Free;
  end;
  Assert.IsTrue(R.OK, 'recuperação que falha é aviso, não erro do banco');
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')),
    'marcador fica para tentar destravar de novo na próxima execução');
end;

procedure TTesteBackup.TestExecutarConcorrenteSaiComAviso;
var
  Bk: TBackup;
  Mutex: THandle;
  Texto: string;
begin
  AddBanco('AG');
  Mutex := CreateMutex(nil, True, PChar(TBackup.NomeMutexExecucao));
  Assert.AreNotEqual(THandle(0), Mutex);
  try
    Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
    try
      Bk.Agora := EncodeDate(2026, 10, 5);
      FLog.Agora := Bk.Agora;
      Bk.EspacoLivreFixo := High(Int64);
      Assert.IsFalse(Bk.Executar);
    finally
      Bk.Free;
    end;
  finally
    ReleaseMutex(Mutex);
    CloseHandle(Mutex);
  end;
  Assert.AreEqual(0, FChamadas.Count, 'nada executado');
  Texto := TFile.ReadAllText(TLog.NomeArquivo(FDestino, EncodeDate(2026, 10, 5)));
  Assert.Contains(Texto, 'em andamento');
end;

procedure TTesteBackup.TestStatusUsaHoraDeInicio;
var
  Bk: TBackup;
  R: TArray<TResultadoBanco>;
  Inicio: TDateTime;
begin
  AddBanco('AG');
  SetLength(R, 1);
  Inicio := EncodeDate(2026, 10, 5) + EncodeTime(23, 50, 0, 0);
  R[0].Nome := 'AG'; R[0].Inicio := Inicio; R[0].Fim := Inicio + EncodeTime(0, 20, 0, 0); R[0].OK := True;
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := R[0].Fim;   // já é o dia seguinte, 00:10
    Bk.GravarStatus(R, Inicio);
  finally
    Bk.Free;
  end;
  Assert.AreEqual(Inicio, TBackup.LerUltimaExecucao(FDestino), 0.00001,
    'UltimaExecucao deve ser a hora de início, senão o timer pula o dia seguinte');
end;

procedure TTesteBackup.TestMarcadorExisteDuranteLock;
var
  Bk: TBackup;
begin
  // Se o processo cair entre o -L e a gravação do marcador, ninguém destrava o banco:
  // o marcador tem que existir ANTES do -L (e sumir se o -L falhar, já coberto).
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    Assert.IsTrue(Bk.ExecutarBanco(FConfig.Bancos[0]).OK);
  finally
    Bk.Free;
  end;
  Assert.IsTrue(FMarcadorNoLock, 'marcador deve existir durante o nbackup -L');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG.lock-pendente')));
end;

procedure TTesteBackup.TestRetencaoUsaDataDoNomeNaoDoArquivo;
var
  Bk: TBackup;
  Hoje: TDateTime;
begin
  // CopyFile preserva a data da origem e o -F pode falhar: a data confiável é a do nome.
  AddBanco('AG');
  FConfig.RetencaoDias := 7;
  Hoje := EncodeDate(2026, 10, 20) + EncodeTime(2, 0, 0, 0);
  CriarArquivo('AG_2026-10-01_0200.fbk', Hoje);          // nome velho, arquivo "novo": apaga
  CriarArquivo('AG_2026-10-20_0200.fdb', Hoje - 30);     // nome de hoje, arquivo "velho": mantém
  CriarArquivo('AG_2026-10-13_0159.fbk', Hoje);          // 1 min além do limite (13/10 02:00): apaga
  CriarArquivo('AG_2026-10-13_0200.fdb', Hoje - 30);     // exatamente no limite: mantém
  CriarArquivo('backup_2026-10-20.log', Hoje - 30);      // log de hoje: mantém
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := Hoje;
    Bk.AplicarRetencao;
  finally
    Bk.Free;
  end;
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-01_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-20_0200.fdb')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-13_0159.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-13_0200.fdb')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'backup_2026-10-20.log')));
end;

procedure TTesteBackup.TestExecutarComDestinoInvalidoNaoLevanta;
var
  Bk: TBackup;
  Ok: Boolean;
begin
  AddBanco('AG');
  FConfig.Destino := 'Z:\pasta\que\nao\existe';
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Ok := True;
    Assert.WillNotRaise(procedure begin Ok := Bk.Executar; end);
    Assert.IsFalse(Ok);
  finally
    Bk.Free;
  end;
end;

procedure TTesteBackup.TestCopiaInformaProgresso;
var
  Bk: TBackup;
  Chamadas: Integer;
  UltCopiados, UltTotal, Tamanho: Int64;
  Conteudo: TBytes;
begin
  AddBanco('AG');
  FConfig.CopiaFbk := False;
  // Arquivo grande o bastante para o CopyFileEx chamar o progresso mais de uma vez
  SetLength(Conteudo, 3 * 1024 * 1024);
  TFile.WriteAllBytes(FConfig.Bancos[0].Arquivo, Conteudo);
  Tamanho := Length(Conteudo);
  Chamadas := 0;
  UltCopiados := -1;
  UltTotal := -1;
  Bk := TBackup.Create(FConfig, FLog, ExecutorFalso());
  try
    Bk.EspacoLivreFixo := High(Int64);
    Bk.OnProgresso := procedure(ACopiados, ATotal: Int64)
      begin
        Inc(Chamadas);
        UltCopiados := ACopiados;
        UltTotal := ATotal;
      end;
    Assert.IsTrue(Bk.ExecutarBanco(FConfig.Bancos[0]).OK);
  finally
    Bk.Free;
  end;
  Assert.IsTrue(Chamadas >= 2, 'progresso chamado ' + IntToStr(Chamadas) + ' vez(es)');
  Assert.AreEqual(Tamanho, UltTotal, 'total da última chamada');
  Assert.AreEqual(Tamanho, UltCopiados, 'copiados na última chamada');
  Assert.AreEqual(Tamanho, Int64(Length(TFile.ReadAllBytes(TDirectory.GetFiles(FDestino, 'AG_*.fdb')[0]))),
    'cópia íntegra');
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteBackup);

end.
