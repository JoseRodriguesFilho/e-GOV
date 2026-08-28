# LabCPFProvider v4

Fluxo de teste:

```text
Acesso do Aluno

CPF
[____________]

[ Entrar ]
```

CPF autorizado nesta versão:

```text
12345678909
```

Conta Windows usada internamente:

```text
.\AlunoLab
```

Senha de teste:

```text
Lab@Teste2026!
```

## Compilar

Suba os arquivos no GitHub e execute:

**Actions -> Build LabCPFProvider x64 v4 -> Run workflow**

Artifact esperado:

```text
LabCPFProvider-x64-v4
```

## Teste seguro

Teste primeiro em VM Windows 11 Pro com snapshot.

Na VM:

1. Execute `CRIAR_CONTA_TESTE.cmd`.
2. Confirme que `.\AlunoLab` entra manualmente.
3. Copie `LabCPFProvider.dll` para `C:\Windows\System32\LabCPFProvider.dll`.
4. Mantenha uma conta administrativa nativa funcionando.
5. Importe `register.reg`.
6. Pressione Win+L.
7. Escolha `Acesso do Aluno`.
8. Teste o CPF `12345678909`.
9. Teste outro CPF e confirme que é recusado.

Para remover, importe `unregister.reg`, reinicie e apague a DLL.

## Atenção

Esta v4 é POC. A senha fixa existe só para comprovar o fluxo. Na versão de produção ela deve sair da DLL e o CPF deverá ser validado por API.
