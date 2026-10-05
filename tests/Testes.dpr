program Testes;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  pTesteSanidade in 'pTesteSanidade.pas',
  pConfig in '..\src\pConfig.pas',
  pTesteConfig in 'pTesteConfig.pas',
  pLog in '..\src\pLog.pas',
  pTesteLog in 'pTesteLog.pas',
  pProcesso in '..\src\pProcesso.pas',
  pTesteProcesso in 'pTesteProcesso.pas',
  pBackup in '..\src\pBackup.pas',
  pTesteBackup in 'pTesteBackup.pas';

var
  Runner: ITestRunner;
  Logger: ITestLogger;
  Resultados: IRunResults;
begin
  try
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    Resultados := Runner.Execute;
    if not Resultados.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
