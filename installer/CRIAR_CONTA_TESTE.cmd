@echo off
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)

echo Criando/ajustando conta local AlunoLab...
net user AlunoLab "Lab@Teste2026!" /add /passwordchg:no >nul 2>&1
if %errorlevel% neq 0 (
  net user AlunoLab "Lab@Teste2026!" >nul 2>&1
)

net localgroup Administradores AlunoLab /delete >nul 2>&1
net localgroup Administrators AlunoLab /delete >nul 2>&1

echo.
echo Conta AlunoLab pronta.
echo Senha de TESTE: Lab@Teste2026!
echo Nao use esta senha em producao.
pause
