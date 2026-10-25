# GymTrainer: personal trainer virtual com Apple Watch e app Saúde

Aplicativo de acompanhamento de treinos em academia com:

- **Contagem de calorias** por treino, usando a energia ativa medida pelo Apple Watch, a frequência cardíaca (Keytel 2005) ou o MET da atividade, nessa ordem de prioridade.
- **Sincronização com o app Saúde (HealthKit) e com o Apple Watch**: frequência cardíaca ao vivo, energia ativa, passos, FC de repouso, HRV, VO2máx, peso, % de gordura, massa magra e treinos.
- **Personal trainer virtual** com formação em Educação Física e Nutrição:
  - **Avaliação física bimestral** (a cada 60 dias): dobras cutâneas (Jackson & Pollock 3 ou 7 dobras + Siri), circunferências (método da Marinha dos EUA), IMC, relação cintura-quadril, massa magra/gorda, TMB/GET, metas de macros, zonas de FC (Karvonen) e **comparação com a avaliação anterior**.
  - **Triagem de exames e PAR-Q**: pressão arterial (Diretrizes SBC 2020), glicemia/HbA1c, perfil lipídico, vitamina D e ferritina geram alertas e **restrições na ficha**. Exemplo: com hipertensão não controlada, o app evita Valsalva e cargas máximas e não prescreve HIIT; com dor lombar, troca terra e agachamento livre por leg press e hip thrust.
  - **Fichas de treino automáticas** baseadas na avaliação: divisão (full body, superiores/inferiores ou push/pull/legs), séries, reps, descanso, RIR, cadência, periodização de 8 semanas com deload, cardio com tempo, zona e bpm-alvo, opção de HIIT e estimativa de kcal.
  - **Demonstração de execução de cada exercício** (46 exercícios, incluindo cardio): passo a passo com reprodução automática, metrônomo de cadência, respiração, pontos-chave, erros comuns, substitutos e link para vídeo.
  - **Coach com IA** (Claude) para conversar sobre treino, nutrição e evolução, usando os dados reais do aluno.

## Estrutura

```
apps/gym-trainer/
├── backend/                 API FastAPI (o "cérebro" do personal trainer)
│   ├── app/science.py       Equações de fisiologia e nutrição
│   ├── app/exercises.py     Catálogo de exercícios + demonstrações
│   ├── app/assessment.py    Avaliação bimestral, triagem de exames, evolução
│   ├── app/planner.py       Montagem da ficha (ACSM) + cardio por zonas
│   ├── app/calories.py      Gasto calórico da sessão
│   ├── app/coach.py         Personal/nutricionista com IA
│   ├── app/main.py          Endpoints
│   └── tests/
├── web/index.html       Versão web de demonstração (abre no navegador)
└── ios/                     App SwiftUI para iPhone e Apple Watch
    ├── project.yml          Projeto XcodeGen (HealthKit, background delivery, workout-processing)
    ├── Shared/              Modelos compartilhados
    ├── GymTrainer/          iPhone: HealthKit, painel, ficha, demonstrações, avaliação, coach
    └── GymTrainerWatch/     Apple Watch: HKWorkoutSession ao vivo, séries, descanso, zona de FC
```

## Como rodar

### Backend

```bash
cd apps/gym-trainer/backend
python -m venv .venv && source .venv/bin/activate
pip install -e ".[test]"
export ANTHROPIC_API_KEY=...   # opcional: ativa o Coach com IA
fastapi dev app/main.py        # documentação interativa em http://localhost:8000/docs
pytest
```

Principais endpoints:

| Método | Rota | Função |
|---|---|---|
| POST | `/users` | Cadastro (objetivo, experiência, dias/semana, lesões) |
| POST | `/users/{id}/assessments` | Avaliação bimestral, que também gera uma nova ficha |
| GET | `/users/{id}/assessments/status` | Dias até a próxima avaliação |
| GET | `/users/{id}/plans/current` | Ficha atual com demonstrações |
| POST | `/users/{id}/workouts` | Registra treino e calcula calorias |
| POST | `/users/{id}/health/sync` | Recebe dados do app Saúde/Apple Watch (sem duplicar treinos) |
| GET | `/users/{id}/summary/weekly` | Treinos, kcal, minutos e volume dos últimos 7 dias |
| POST | `/users/{id}/coach/chat` | Conversa com o Coach (IA) |
| GET | `/exercises` | Catálogo com execução detalhada |

### iPhone + Apple Watch

Requisitos: Mac com Xcode 15 ou superior, iPhone com iOS 17 ou superior e Apple Watch com watchOS 10 ou superior.

```bash
brew install xcodegen
cd apps/gym-trainer/ios
xcodegen generate
open GymTrainer.xcodeproj
```

1. Em *Signing & Capabilities*, selecione o seu Team nos dois targets. A capability HealthKit já vem configurada.
2. Rode no iPhone (o simulador não tem dados reais de FC). Na primeira abertura, informe a URL da API (o IP do seu Mac na rede, ex.: `http://192.168.0.10:8000`) e autorize o acesso ao app Saúde.
3. Faça a avaliação física. A ficha é gerada e enviada automaticamente ao relógio.
4. No Apple Watch, escolha o dia da ficha. O relógio mede FC e calorias ao vivo, guia as séries com timer de descanso e vibra se a FC sair da zona-alvo no cardio. No fim, o treino é gravado no app Saúde e enviado ao iPhone/API.

## Base científica usada pelo Coach

| Tema | Referência |
|---|---|
| Treino de força (frequência, faixas de RM, progressão de 2-10%) | ACSM Position Stand, *Progression Models in Resistance Training for Healthy Adults* (Ratamess et al., 2009). Uma atualização do ACSM foi publicada em 2026. |
| Volume para hipertrofia (10 ou mais séries/semana por músculo) | Schoenfeld, Ogborn & Krieger (2017) |
| Aeróbio para saúde/emagrecimento (150-300 min/semana) | Diretrizes da OMS (2020) / ACSM |
| % de gordura por dobras | Jackson & Pollock (1978), Jackson, Pollock & Ward (1980), equação de Siri (1961) |
| % de gordura por circunferências | Hodgdon & Beckett (1984), Marinha dos EUA |
| Classificação de % de gordura | American Council on Exercise (ACE) |
| Taxa metabólica basal | Mifflin-St Jeor (1990); Katch-McArdle quando há massa magra |
| FC máxima e zonas | Tanaka et al. (2001); Karvonen (1957) |
| Calorias pela FC | Keytel et al. (2005), *J Sports Sci* 23(3):289-97, modelo sem VO2máx (kJ/min ÷ 4,184) |
| MET das atividades | *2024 Adult Compendium of Physical Activities* (Herrmann et al.) |
| Proteína | ISSN Position Stand (Jäger et al., 2017); Helms et al. (2014) para fase de déficit |
| Pressão arterial | Diretrizes Brasileiras de Hipertensão Arterial (SBC, 2020) |
| Triagem pré-participação | PAR-Q |
| Sessão de treino no Apple Watch | Apple, *Running workout sessions* (HKWorkoutSession / HKLiveWorkoutBuilder) |

> **Aviso:** o GymTrainer é uma ferramenta de apoio. Ele não substitui a avaliação presencial de um médico, de um nutricionista (CRN) ou de um profissional de Educação Física (CREF). Alertas de saúde gerados pelo app (PA elevada, glicemia alterada, PAR-Q positivo) devem ser levados a um médico.
