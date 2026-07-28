# The one shared C++ test runner.
#
# It links the core static library and runs without any frontend, which is what
# docs/architecture.md requires of it on every development platform. It has no
# third-party dependency and fetches nothing, so it configures and builds the
# same way on a machine that has only a compiler and CMake.

add_executable(mxq_core_tests
  main.cpp
  mxq_fixture.cpp
  mxq_json.cpp
  mxq_rules_facade.cpp
)

target_link_libraries(mxq_core_tests PRIVATE mxq::core mxq_warnings)

# fixtures/ lives at the repository root rather than under core/: it is the
# independent authority the core is validated against, not an implementation
# detail of the core it validates. The path below is only the default; the
# runner also accepts --fixtures and $MXQ_FIXTURES_DIR, which is how CI points
# it at a checkout in another location.
target_compile_definitions(mxq_core_tests PRIVATE
  MXQ_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/rules"
  MXQ_TEST_RULES_FACADE=$<IF:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,1,0>
)

add_test(NAME rules_fixtures
         COMMAND mxq_core_tests
                 --junit "${CMAKE_CURRENT_BINARY_DIR}/rules-fixtures.xml")
set_tests_properties(rules_fixtures PROPERTIES
  LABELS "rules;fixtures"
)
